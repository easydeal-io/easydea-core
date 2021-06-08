// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

import {ESDStorage} from "./ESDStorage.sol";
import {IBEP20} from "./itf/IBEP20.sol";
import {SafeMath} from "./lib/SafeMath.sol";
import {SafeBEP20} from "./lib/SafeBEP20.sol";

contract Easydeal is ESDStorage {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // ============ Events ============

    event PostInfo(uint32 spaceId, address indexed owner, string title, string content, uint256 price);
    event MakeDeal(uint32 infoId, address indexed maker);

    // ============ Modifiers ============

    modifier onlyRegistered() {
        require(users[msg.sender].status == 1, "user status incorrect");
        _;
    }

    modifier onlyMerchant() {
        require(
            users[msg.sender].status == 1 && users[msg.sender].isMerchant, 
            "merchant satus incorrect"
        );
        _;
    }

    modifier onlyCouncilMember() {
        require(
            councilMemberAddresses.length == 0 || (
                users[msg.sender].status == 1 && users[msg.sender].isCouncilMember
            ), 
            "council member status incorrect"
        );
        _;
    }

    modifier verifyUser(address addr, uint8 status) {
        require(users[addr].timestamp > 0 && users[addr].status == status, "user status incorrect");
        _;
    }

    constructor(address esdTokenAddress) {
        ESDToken = IBEP20(esdTokenAddress);
    }

    // ============ Public functions ============

    /**
        User register
        When a council member guarantee for him, he will get the tips
     */
    function registerUser(
        string memory nickName, 
        string memory socialLink, 
        string memory bio
    ) public {
        require(registerQueue.length < registerQueueSize, "register queue size limit");
        require(users[msg.sender].timestamp == 0, "you are already in the queue");

        users[msg.sender] = User({
            nickName: nickName,
            socialLink: socialLink,
            bio: bio,
            lockedBeginTimestamp: 0,
            lockedTokenAmount: 0,
            isMerchant: false,
            isCouncilMember: false,
            guarantor: address(0),
            score: 0,
            timestamp: block.timestamp,
            status: 0
        });

        registerQueue.push(msg.sender);
    }

    function applyMerchant() public onlyRegistered {
        require(users[msg.sender].lockedTokenAmount >= merchantMinimumLockAmount, "locked amount not enough");
        require(!users[msg.sender].isCouncilMember, "you are council member");
        users[msg.sender].isMerchant = true;
    }

    function postInfo(
        uint32 spaceId, 
        uint8 iType,
        string memory title, 
        string memory content, 
        string memory memo,
        address acceptToken,
        uint256 qty,
        uint256 price
    ) public onlyMerchant payable returns (uint32) {
      
        require(price > 0, "invalid price");
        require(qty > 0, "qty is zero");

        Space storage space = spaces[spaceId];
        require(space.status == 1, "space status incorrect");

        if (iType == 1) {
            if (acceptToken == address(0)) {
                require(msg.value == price * qty, "deposit value is not enough");
            } else {
                IBEP20 acceptTokenContract = IBEP20(acceptToken);
                require(acceptTokenContract.balanceOf(msg.sender) > price, "insufficient balance");
                acceptTokenContract.safeTransferFrom(msg.sender, address(this), price * qty);
            }
            
        }
        infoCount++;
        infos[infoCount] = Info({
            id: infoCount,
            spaceId: spaceId,
            iType: iType,
            title: title,
            content: content,
            memo: memo,
            owner: msg.sender,
            price: price,
            qty: qty,
            acceptToken: acceptToken,
            timestamp: block.timestamp,
            status: 1
        });

        space.infos++;
        emit PostInfo(spaceId, msg.sender, title, content, price);

        return infoCount;
    }

    function makeDeal(
        uint32 infoId, 
        uint qty
    ) public onlyRegistered payable {
       
        Info storage info = infos[infoId];
        require(info.status == 1, "info status incorrect");

        require(info.qty >= qty, "insufficient qty");

        Space storage space = spaces[info.spaceId];
        require(space.status == 1, "space status is incorrect");

        if (info.iType == 0) {
            if (info.acceptToken == address(0)) {
                require(msg.value == info.price * qty, "deposit value is not enough");
            } else {
                uint tokenBalance = ESDToken.balanceOf(msg.sender);
                require(tokenBalance >= info.price * qty, "insufficient balance");
                ESDToken.safeTransferFrom(msg.sender, address(this), info.price * qty);
            }
        }

        dealCount++;
        deals[dealCount] = Deal({
            id: dealCount,
            infoId: infoId,
            qty: qty,
            maker: msg.sender,
            timestamp: block.timestamp,
            status: 1
        });

        info.qty--;
        space.deals++;

        emit MakeDeal(infoId, msg.sender);
    }

    function followSpace(uint32 id) public onlyRegistered {
        Space storage space = spaces[id]; 
        require(space.status == 1, "space status incorrect");

        uint32[] storage ids = followedSpaceIds[msg.sender];
        for (uint i = 0; i < ids.length; i++) {
            if (ids[i] == id) {
                revert("you have followed this space");
            }
        }
        
        space.follows++;
        ids.push(id);
    }

    function unFollowSpace(uint32 id) public onlyRegistered {
        uint32[] memory ids = followedSpaceIds[msg.sender];
        bool changed = false;
        for (uint256 i = 0; i < ids.length; i++) {
            if (ids[i] == id) {
                ids[i] = ids[ids.length - 1];
                changed = true;
                break;
            }
        }
        if (changed) {
            followedSpaceIds[msg.sender] = ids;
            followedSpaceIds[msg.sender].pop();
        }
    }

    /**
        Add space by council member
     */
    function addSpace(
        string memory name, 
        string memory description, 
        uint32 feeRate
    ) public onlyCouncilMember {
        require(feeRate <= 100, "fee rate too high");
        spaceCount++;
        spaces[spaceCount] = Space({
            id: spaceCount,
            name: name,
            description: description,
            creator: tx.origin,
            infos: 0,
            deals: 0,
            follows: 0,
            feeRate: feeRate,
            timestamp: block.timestamp,
            status: 1
        });
    }

    /**
        Hide space by creator
     */
    function hideSpace(uint32 id) public onlyCouncilMember {
        require(tx.origin == spaces[id].creator, "Easydeal: FORBIDDEN");
        spaces[id].status = 0;
    }

    /**
        Guarantee an user by council member
     */
    function guaranteeUser(address addr) public onlyCouncilMember verifyUser(addr, 0) {
        users[addr].guarantor = msg.sender;
        users[addr].status = 1;
        _removeAddressFromReqisterQueue(addr);
    }

    /**
        Reject an user register by council member
     */
    function rejectUserRegister(address addr) public onlyCouncilMember verifyUser(addr, 0) {
        _removeAddressFromReqisterQueue(addr);
        delete users[addr];
    }

    /**
        Ban an user register by council member
     */
    function banUser(address addr) public onlyCouncilMember verifyUser(addr, 1) {
        users[addr].status = 2;
    }

    /**
        Call other contract
     */
    function call(
        address targetContract, 
        bytes calldata callData
    ) public onlyRegistered {
        bytes4 selector = getSelector(callData);
        CallProxy memory proxy = callProxies[targetContract][selector];
        require(proxy.timestamp > 0 && !proxy.viaProposal, "Easydeal: FORBIDDEN");
        (bool success, ) = targetContract.call(callData);
        require(success, "function call failed");
    }

    /**
        Submit a proposal
     */
    function submitProposal(
        uint tipsAmount, 
        address targetContract,
        string memory title,
        string memory description,
        bytes calldata callData
    ) public onlyRegistered {
        
        require(!haveReferendum[msg.sender], "you have a referendum");
        require(tipsAmount >= proposalTipsMinAmount, "tips amount is not enough");
        if (targetContract != address(this)) {
            bytes4 selector = getSelector(callData);
            CallProxy memory proxy = callProxies[targetContract][selector];
            require(proxy.timestamp > 0 && proxy.viaProposal, "Easydeal: FORBIDDEN");
        }

        uint tokenBalance = ESDToken.balanceOf(msg.sender);
        require(tokenBalance >= tipsAmount, "insufficient token balance");
        ESDToken.safeTransferFrom(msg.sender, address(this), tipsAmount);

        proposalCount++;
        proposals[proposalCount] = Proposal({
            id: proposalCount,
            targetContract: targetContract,
            proposer: msg.sender,
            tipsAmount: tipsAmount,
            ayesAttachedTokenAmount: 0,
            naysAttachedTokenAmount: 0,
            title: title,
            description: description,
            callData: callData,
            votingDeadlineTimestamp: block.timestamp + proposalVotingDuration,
            councilMembersAtThatTime: uint32(councilMemberAddresses.length),
            timestamp: block.timestamp,
            status: 1
        });

        haveReferendum[msg.sender] = true;
    }

    function voteOnProposal(uint32 pid, bool aye) public onlyRegistered {
       
        Proposal storage proposal = proposals[pid];
        require(proposal.status == 1, "proposal isn't exist");

        uint attachedTokenAmount = proposal.tipsAmount.mul(votingAttachedTokenFactor).div(100);
        require(ESDToken.balanceOf(msg.sender) >= attachedTokenAmount, "insufficient token balance");

        address[] storage ayes = proposalAyes[pid];
        address[] storage nays = proposalNays[pid];

        for (uint i = 0; i < ayes.length; i++) {
            if (ayes[i] == msg.sender) {
                revert("you have voted aye");
            }
        }

        for (uint i = 0; i < nays.length; i++) {
            if (nays[i] == msg.sender) {
                revert("you have voted nay");
            }
        }

        ESDToken.safeTransferFrom(msg.sender, address(this), attachedTokenAmount);

        if (aye) {
            ayes.push(msg.sender);
            proposal.ayesAttachedTokenAmount += attachedTokenAmount;
        } else {
            nays.push(msg.sender);
            proposal.naysAttachedTokenAmount += attachedTokenAmount;
        }

        // voting deadline
        if (block.timestamp > proposal.votingDeadlineTimestamp) {
            
            haveReferendum[proposal.proposer] = false;
            uint averageAttachedTokenPerUser = proposal.naysAttachedTokenAmount.add(proposal.ayesAttachedTokenAmount);
            uint tipsPerUser = 0;

            if (ayes.length > nays.length) {
                // forward to council member seconds
                averageAttachedTokenPerUser = averageAttachedTokenPerUser.div(ayes.length);
                tipsPerUser = proposal.tipsAmount.div(ayes.length);

                for (uint i = 0; i < ayes.length; i++) {
                    ESDToken.safeTransfer(ayes[i], averageAttachedTokenPerUser.add(tipsPerUser));
                }

                proposal.status = 3;

            } else {
                // defeated
                averageAttachedTokenPerUser = averageAttachedTokenPerUser.div(nays.length);
                tipsPerUser = proposal.tipsAmount.div(nays.length);

                for (uint i = 0; i < nays.length; i++) {
                    ESDToken.safeTransfer(nays[i], averageAttachedTokenPerUser.add(tipsPerUser));
                }

                proposal.status = 2;
            }
           
        }
        proposal.councilMembersAtThatTime = uint32(councilMemberAddresses.length);
    }

    /**
        Council member second on a proposal

        If the number of seconds greater than half of the members, the proposal will be executed
     */

    function secondOnProposal(uint32 pid) public onlyCouncilMember {
        Proposal storage proposal = proposals[pid];
        require(proposal.status == 3, "proposal status incorrect");
        address[] storage _seconds = proposalSeconds[pid];
        for (uint i = 0; i < _seconds.length; i++) {
            require(_seconds[i] != msg.sender, "you have already second");
        }
        _seconds.push(msg.sender);

        uint32 halfOfMembers = uint32(councilMemberAddresses.length)/2;
        if (_seconds.length > halfOfMembers) {
            // execute
            (bool success, ) = proposal.targetContract.call(proposal.callData);
            require(success, "execute failed");
             proposal.status = 4;
        }
        proposal.councilMembersAtThatTime = uint32(councilMemberAddresses.length);
    }

    function lockToken(uint256 amount) public onlyRegistered {
        require(amount > 0, "amount is zero");
        User storage user = users[msg.sender];
        require(ESDToken.balanceOf(msg.sender) >= amount, "insufficient balance");
        ESDToken.safeTransferFrom(msg.sender, address(this), amount);
        if (user.lockedBeginTimestamp == 0) {
            user.lockedBeginTimestamp = block.timestamp;
        }
        user.lockedTokenAmount += amount;
        totalLockedTokenAmount += amount;
    }

    function unlockToken(uint256 amount) public onlyRegistered {
        require(amount > 0, "amount is zero");
        User storage user = users[msg.sender];
        require(user.lockedTokenAmount >= amount, "not enough");
        ESDToken.safeTransfer(msg.sender, amount);
        user.lockedBeginTimestamp = block.timestamp;
        user.lockedTokenAmount -= amount;
        totalLockedTokenAmount -= amount;
        if (user.isMerchant && user.lockedTokenAmount < merchantMinimumLockAmount) {
            user.isMerchant = false;
        } else if (user.isCouncilMember && user.lockedTokenAmount < councilMemberMinimumLockAmount) {
            user.isCouncilMember = false;
        }
    }
    
    // ============ Proposal execute functions ============

    /**
        Apply to be council member
     */
    function applyCouncilMember(address addr) external {
        require(msg.sender == address(this), "Easydeal: FORBIDDEN");
        User storage user = users[addr];
        require(!user.isMerchant, "merchant can't be council member");
        require(user.status == 1, "user status incorrect");
        require(user.lockedTokenAmount >= councilMemberMinimumLockAmount, "amount isn't enough");
        require(councilMemberAddresses.length < maximumCouncilMembers, "council members limit");
        user.isCouncilMember = true;
        councilMemberAddresses.push(addr);
    }

    function registerCallProxy(address targetAddress, bytes4 selector, bool viaProposal) external {
        require(msg.sender == address(this), "Easydeal: FORBIDDEN");
        callProxies[targetAddress][selector] = CallProxy({
            viaProposal: viaProposal,
            timestamp: block.timestamp
        });
    }

    // ============ Private functions ============

    function getSelector(bytes memory _data) private pure returns(bytes4 sig) {
        assembly {
            sig := mload(add(_data, 32))
        }
    }

}