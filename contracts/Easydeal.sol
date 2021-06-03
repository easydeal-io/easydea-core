// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

import {ESDStorage} from "./ESDStorage.sol";
import {IBEP20} from "./itf/IBEP20.sol";
import {SafeMath} from "./lib/SafeMath.sol";
import {SafeBEP20} from "./lib/SafeBEP20.sol";
import {Address} from "./lib/Address.sol";

contract Easydeal is ESDStorage {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    using Address for address;

    // ============ Events ============

    event PostInfo(uint32 spaceId, address indexed owner, string title, string content, uint256 price);
    event MakeDeal(uint32 infoId, address indexed maker);

    // ============ Modifiers ============

    modifier onlyRegistered() {
        require(users[msg.sender].status == 1, "user is not registered or status is incorrect");
        _;
    }

    modifier onlyMerchant() {
        require(
            users[msg.sender].status == 1 && users[msg.sender].isMerchant, 
            "user is not merchant or status is incorrect"
        );
        _;
    }

    modifier onlyCouncilMember() {
        require(
            councilMembers.length == 0 || (
                users[msg.sender].status == 1 && users[msg.sender].isCouncilMember
            ), 
            "council member is not merchant or status is incorrect"
        );
        _;
    }

    constructor(address _esdTokenAddress) {
        esdTokenAddress = _esdTokenAddress;
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
        require(users[msg.sender].timestamp == 0, "you are already in the register queue");

        users[msg.sender] = User({
            nickName: nickName,
            socialLink: socialLink,
            bio: bio,
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
        require(space.status == 1, "space isn't exist or status is incorrect");

        if (iType == 1) {
            if (acceptToken == address(0)) {
                require(msg.value == price * qty, "deposit value is not enough");
            } else {
                IBEP20 acceptTokenContract = IBEP20(acceptToken);
                require(acceptTokenContract.balanceOf(msg.sender) > price, "insufficient balance to deposit");
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
        require(info.status == 1, "info isn't exist or status is incorrect");

        require(info.qty >= qty, "insufficient qty");

        Space storage space = spaces[info.spaceId];
        require(space.status == 1, "space status is incorrect");

        if (info.iType == 0) {
            if (info.acceptToken == address(0)) {
                require(msg.value == info.price * qty, "deposit value is not enough");
            } else {
                IBEP20 token = IBEP20(esdTokenAddress);
                uint tokenBalance = token.balanceOf(msg.sender);

                require(tokenBalance >= info.price * qty, "insufficient balance to make deal");
                token.safeTransferFrom(msg.sender, address(this), info.price * qty);
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
        require(space.status == 1, "space isn't exist or status is incorrect");

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
        Space storage space = spaces[id];
        require(tx.origin == space.creator, "you are not the space creator");
        space.status = 0;
    }

    /**
        Guarantee an user by council member
     */
    function guaranteeUser(address _address) public onlyCouncilMember {
        User storage user = users[_address];
        require(user.timestamp > 0 && user.status == 0, "user is not registered or status is incorrect");

        user.guarantor = msg.sender;
        user.status = 1;
        _removeAddressFromReqisterQueue(_address);
    }

    /**
        Reject an user register by council member
     */
    function rejectUserRegister(address _address) public onlyCouncilMember {
        User storage user = users[_address];
        require(user.timestamp > 0 && user.status == 0, "user is not registered or status is incorrect");

        _removeAddressFromReqisterQueue(_address);
        delete users[_address];
    }

    /**
        Ban an user register by council member
     */
    function banUser(address _address) public onlyCouncilMember {
        User storage user = users[_address];
        require(user.timestamp > 0 && user.status == 1, "user is not registered or status is incorrect");
        user.status = 2;
    }

    /**
        Submit a proposal
     */
    function submitProposal(
        uint tipsAmount, 
        string memory title,
        string memory description,
        bytes calldata callData
    ) public onlyRegistered {
        
        require(!haveReferendum[msg.sender], "you have a referendum");

        require(tipsAmount >= proposalTipsMinAmount, "tips amount is not enough");

        IBEP20 token = IBEP20(esdTokenAddress);
        uint tokenBalance = token.balanceOf(msg.sender);

        require(tokenBalance >= tipsAmount, "insufficient token balance for tip");
        token.safeTransferFrom(msg.sender, address(this), tipsAmount);

        proposalCount++;
        proposals[proposalCount] = Proposal({
            id: proposalCount,
            proposer: msg.sender,
            tipsAmount: tipsAmount,
            ayesAttachedTokenAmount: 0,
            naysAttachedTokenAmount: 0,
            title: title,
            description: description,
            callData: callData,
            expireTimestamp: block.timestamp + proposalVotingDuration,
            timestamp: block.timestamp,
            status: 1
        });

        haveReferendum[msg.sender] = true;
    }

    function voteOnProposal(uint32 pId, bool aye) public onlyRegistered {
       
        Proposal storage proposal = proposals[pId];
        require(proposal.status == 1, "proposal isn't exist or status is incorrect");

        IBEP20 token = IBEP20(esdTokenAddress);
        uint attachedTokenAmount = proposal.tipsAmount.mul(votingAttachedTokenFactor).div(100);

        require(token.balanceOf(msg.sender) >= attachedTokenAmount, "insufficient token balance for attached");

        address[] storage ayes = proposalAyes[pId];
        address[] storage nays = proposalNays[pId];

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

        token.safeTransferFrom(msg.sender, address(this), attachedTokenAmount);

        if (aye) {
            ayes.push(msg.sender);
            proposal.ayesAttachedTokenAmount += attachedTokenAmount;
        } else {
            nays.push(msg.sender);
            proposal.naysAttachedTokenAmount += attachedTokenAmount;
        }

        // voting deadline
        if (block.timestamp > proposal.expireTimestamp) {
            
            haveReferendum[proposal.proposer] = false;
            uint averageAttachedTokenPerUser = proposal.naysAttachedTokenAmount.add(proposal.ayesAttachedTokenAmount);
            uint tipsPerUser = 0;

            if (ayes.length > nays.length) {
                // forward to council member seconds
                averageAttachedTokenPerUser = averageAttachedTokenPerUser.div(ayes.length);
                tipsPerUser = proposal.tipsAmount.div(ayes.length);

                for (uint i = 0; i < ayes.length; i++) {
                    token.safeTransfer(ayes[i], averageAttachedTokenPerUser.add(tipsPerUser));
                }

                proposal.status = 3;

            } else {
                // defeated
                averageAttachedTokenPerUser = averageAttachedTokenPerUser.div(nays.length);
                tipsPerUser = proposal.tipsAmount.div(nays.length);

                for (uint i = 0; i < nays.length; i++) {
                    token.safeTransfer(nays[i], averageAttachedTokenPerUser.add(tipsPerUser));
                }

                proposal.status = 2;
            }
           
        }
    }

    /**
        Council member second on a proposal

        If the number of seconds greater than half of the members, the proposal will be executed
     */

    function secondOnProposal(uint32 pId) public onlyCouncilMember {
        Proposal storage proposal = proposals[pId];
        require(proposal.status == 3, "proposal isn't exist or status is incorrect");
        address[] storage _seconds = proposalSeconds[pId];
        _seconds.push(msg.sender);

        uint32 halfOfMembers = uint32(councilMembers.length)/2;
        if (_seconds.length > halfOfMembers) {
            address(this).functionCall(proposal.callData, "execute failed");
        }
    }

}