// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

import {IBEP20} from "./itf/IBEP20.sol";

import {SafeMath} from "./lib/SafeMath.sol";
import {SafeBEP20} from "./lib/SafeBEP20.sol";
import {Context} from "./lib/Context.sol";

/**
 * @title Easydeal User
 * @author flex@easydeal.io
 *
 */

contract ESDUser is Context {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // ============ Structs ============

    struct User {
        string nickName;
        string socialLink;
        string bio;
        uint256 lockedBeginTimestamp;
        uint256 lockedTokenAmount;
        bool isMerchant;
        bool isCouncilMember;
        address guarantor;
        uint256 timestamp;
        uint8 status; // 0 wait for guarantee, 1 normal, 2 banned
    }

    struct Proposal {
        uint32 id;
        address proposer;
        string title;
        string description;
        address targetContract;
        bytes callData;
        uint256 tipsAmount;
        uint256 ayesAttachedTokenAmount;
        uint256 naysAttachedTokenAmount;
        uint256 timestamp;
        uint256 votingDeadlineTimestamp;
        // 1 referendum 2 defeated 3 second 4 executed
        uint8 status; 
    }

    // ============ States ============
    
    IBEP20 ESDToken;
    
    uint256 public immutable genesisBlockTimestamp;
    uint256 public totalLockedTokenAmount;

    address[] registerQueue;
    uint32 public registerQueueSize = 100;

    uint32 public proposalCount = 0;
  
    // council config
    address[] councilMemberAddresses;
    uint32 public maximumCouncilMembers = 13;
    uint256 public proposalTipsMinAmount = 100 * 10 ** 18;
    uint256 public proposalVotingDuration = 1 hours;
    uint256 public merchantMinimumLockAmount = 1000 * 10 ** 18;
    uint256 public councilMemberMinimumLockAmount = 10000 * 10 ** 18;

    uint8 public votingAttachedTokenFactor = 10;
    mapping(address => bool) public haveReferendum;

    mapping(address => User) public users;
    mapping(uint32 => Proposal) public proposals;
    mapping(address => uint32[]) followedSpaceIds;

    mapping(uint32 => address[]) proposalAyes;
    mapping(uint32 => address[]) proposalNays;
    mapping(uint32 => address[]) proposalSeconds;

    address[] lockedWeightsRanking;

    // ============ Events ============

    receive() external payable {
    }

    // ============ Modifiers ============

    modifier onlyRegistered() {
        require(users[msg.sender].status == 1, "FORBIDDEN");
        _;
    }

    modifier onlyMerchant() {
        require(
            users[msg.sender].status == 1 && users[msg.sender].isMerchant, 
            "FORBIDDEN"
        );
        _;
    }

    modifier notCouncilMember() {
        require(
            users[msg.sender].status == 1 && !users[msg.sender].isMerchant, 
            "FORBIDDEN"
        );
        _;
    }

    modifier onlyCouncilMember() {
        require(
            councilMemberAddresses.length == 0 || (
                users[msg.sender].status == 1 && users[msg.sender].isCouncilMember
            ), 
            "status incorrect"
        );
        _;
    }

    modifier verifyUser(address addr, uint8 status) {
        require(users[addr].timestamp > 0 && users[addr].status == status, "status incorrect");
        _;
    }

    constructor (address _esdTokenAddress) {
        ESDToken = IBEP20(_esdTokenAddress);
        genesisBlockTimestamp = block.timestamp;
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
        require(registerQueue.length < registerQueueSize, "queue size limit");
        require(users[msg.sender].timestamp == 0, "exist");
        users[msg.sender] = User({
            nickName: nickName,
            socialLink: socialLink,
            bio: bio,
            lockedBeginTimestamp: 0,
            lockedTokenAmount: 0,
            isMerchant: false,
            isCouncilMember: false,
            guarantor: address(0),
            timestamp: block.timestamp,
            status: 0
        });
        registerQueue.push(msg.sender);
    }

    function applyMerchant() public onlyRegistered {
        User storage user = users[msg.sender];
        require(user.lockedTokenAmount >= merchantMinimumLockAmount, "NOT_ENOUGH_LOCKED_AMOUNT");
        require(user.isCouncilMember, "FORBIDDEN");
       user.isMerchant = true;
    }

    /**
        Guarantee an user by council member
     */
    function guaranteeUser(address addr) public onlyCouncilMember verifyUser(addr, 0) {
        User storage user = users[addr];
        user.guarantor = msg.sender;
        user.status = 1;
        _removeAddressFromReqisterQueue(addr);
    }

    /**
        Reject an user register by council member
     */
    function rejectUserRegister(address addr) public onlyCouncilMember {
        require(users[addr].status == 0, "DENIED");
        delete users[addr];
        _removeAddressFromReqisterQueue(addr);
    }

    /**
        Ban an user register by council member
     */
    function banUser(address addr) public onlyCouncilMember {
        users[addr].status = 2;
    }

    /**
        Submit a proposal
     */
    function submitProposal(
        uint tipsAmount, 
        string memory title,
        string memory description,
        address targetContract,
        bytes calldata callData
    ) public onlyRegistered {
        
        require(!haveReferendum[msg.sender], "you have a referendum");
        require(tipsAmount >= proposalTipsMinAmount, "tips not enough");

        uint tokenBalance = ESDToken.balanceOf(msg.sender);
        require(tokenBalance >= tipsAmount, "insufficient balance");
        ESDToken.safeTransferFrom(msg.sender, address(this), tipsAmount);

        proposals[++proposalCount] = Proposal({
            id: proposalCount,
            proposer: msg.sender,
            title: title,
            description: description,
            targetContract: targetContract,
            callData: callData,
            tipsAmount: 0,
            ayesAttachedTokenAmount: 0,
            naysAttachedTokenAmount: 0,
            timestamp: block.timestamp,
            votingDeadlineTimestamp: block.timestamp.add(proposalVotingDuration),
            status: 1
        });

        haveReferendum[msg.sender] = true;
    }

    function voteOnProposal(uint32 pid, bool aye) public notCouncilMember {
       
        Proposal storage proposal = proposals[pid];
        require(proposal.status == 1, "proposal isn't exist");

        uint attachedTokenAmount = proposal.tipsAmount.mul(votingAttachedTokenFactor).div(100);
        require(ESDToken.balanceOf(msg.sender) >= attachedTokenAmount, "insufficient balance");

        ESDToken.safeTransferFrom(msg.sender, address(this), attachedTokenAmount);
        
        address[] storage ayes = proposalAyes[pid];
        address[] storage nays = proposalNays[pid];
        for (uint i = 0; i < ayes.length; i++) {
            if (ayes[i] == msg.sender) {
                revert("VOTED");
            }
        }
        for (uint i = 0; i < nays.length; i++) {
            if (nays[i] == msg.sender) {
                revert("VOTED");
            }
        }

        if (aye) {
            ayes.push(msg.sender);
            proposal.ayesAttachedTokenAmount = proposal.ayesAttachedTokenAmount.add(attachedTokenAmount);
        } else {
            nays.push(msg.sender);
            proposal.naysAttachedTokenAmount = proposal.naysAttachedTokenAmount.add(attachedTokenAmount);
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
            require(_seconds[i] != msg.sender, "SECONDED");
        }
        _seconds.push(msg.sender);
        uint32 halfOfMembers = uint32(councilMemberAddresses.length)/2;
        if (_seconds.length > halfOfMembers) {
            // execute
            (bool success, ) = proposal.targetContract.call(proposal.callData);
            require(success, "execute failed");
            proposal.status = 4;
        }
    }

    function lockToken(uint256 amount) public onlyRegistered {
        require(amount > 0, "amount is zero");
        User storage user = users[msg.sender];
        
        require(ESDToken.balanceOf(msg.sender) >= amount, "INSUFFICIENT_BALANCE");
        ESDToken.safeTransferFrom(msg.sender, address(this), amount);
        user.lockedTokenAmount = user.lockedTokenAmount.add(amount);
        totalLockedTokenAmount = user.lockedTokenAmount.add(amount);
        if (user.lockedBeginTimestamp == 0) {
            user.lockedBeginTimestamp = block.timestamp;
        }

        updateLockedWeightsRanking(msg.sender);
    }

    function updateLockedWeightsRanking(address addr) internal {
        // check if exist
        bool inArr = false;
        for (uint i = 0; i < lockedWeightsRanking.length; i++) {
            if (lockedWeightsRanking[i] == addr) {
                inArr = true;
            }
        }
        if (!inArr) {
            lockedWeightsRanking.push(addr);
        }
        uint256 llen = lockedWeightsRanking.length;
        if (llen == 1) {
            return;
        }
        // sort
        address[] memory tmpArr = lockedWeightsRanking;
        for (uint256 i = 0; i < llen - 1; i++) {
            for (uint256 j = 0; j < llen - 1 - i; j++) {
                address aa = tmpArr[j];
                address ab = tmpArr[j+1];
                if (computeLockedWeights(aa) > computeLockedWeights(ab)) {
                    tmpArr[j+1] = tmpArr[j];
                    tmpArr[j] = ab;
                }
            }
        }
        lockedWeightsRanking = tmpArr;
        // slice
        if (llen > 10) {
            lockedWeightsRanking.pop();
        }
    }

    function unlockToken(uint256 amount) public onlyRegistered {
        require(amount > 0, "amount is zero");
        User storage user = users[msg.sender];
        require(user.lockedTokenAmount >= amount, "NOT_ENOUGH_LOCED");
        require(
            ESDContext.getActiveDealIds(msg.sender).length == 0 &&
            ESDContext.getActiveInfoIds(msg.sender).length == 0,
            "CAN_NOT_UNLOCK"
        );
        ESDToken.safeTransfer(msg.sender, amount);
        user.lockedTokenAmount = user.lockedTokenAmount.sub(amount);
        totalLockedTokenAmount = user.lockedTokenAmount.sub(amount);
        user.lockedBeginTimestamp = block.timestamp - 1;
        if (
            user.isMerchant && 
            (user.lockedTokenAmount < merchantMinimumLockAmount)
        ) {
            user.isMerchant = false;
        } else if (
            user.isCouncilMember && 
            (user.lockedTokenAmount < councilMemberMinimumLockAmount)
        ) {
            user.isCouncilMember = false;
        }
        updateLockedWeightsRanking(msg.sender);
    }

    // ============ Helper functions ============

    function isValidUser(address addr) public view returns (bool) {
        return users[addr].status == 1;
    }

    function isMerchant(address addr) public view returns (bool) {
        return users[addr].status == 1 && users[addr].isMerchant;
    }

    function isCouncilMember(address addr) public view returns (bool) {
        return users[addr].status == 1 && users[addr].isCouncilMember;
    }

    function getFollowedSpaceIds(address addr) public view returns (uint32[] memory) {
        return followedSpaceIds[addr];
    }

    function followSpace(uint32 id) public onlyRegistered {
        uint32[] storage ids = followedSpaceIds[msg.sender];
        for (uint i = 0; i < ids.length; i++) {
            if (ids[i] == id) {
                revert("FOLLOWED");
            }
        }
        ids.push(id);
        ESDContext.followSpace(id);
    }

    function unfollowSpace(uint32 id) public onlyRegistered {
        uint32[] storage ids = followedSpaceIds[msg.sender];
        for (uint i = 0; i < ids.length; i++) {
            if (ids[i] == id) {
                ids[i] = ids[ids.length - 1];
                ids.pop();
                break;
            }
        }
        ESDContext.unfollowSpace(id);
    }

    function computeLockedWeights(address addr) public view returns (uint32) {
        User memory user = users[addr];
        if (user.status != 1) {
            return 0;
        }
        if (totalLockedTokenAmount == 0 || user.lockedTokenAmount == 0) {
            return 0;
        }
        uint256 lockedTokenWeights = user.lockedTokenAmount.mul(100).div(totalLockedTokenAmount);
        uint256 lockedTimeWeights = (
            block.timestamp - user.lockedBeginTimestamp
        ).mul(100).div(
            block.timestamp - genesisBlockTimestamp
        );
        return uint32(lockedTokenWeights.mul(lockedTimeWeights));
    }

    function _removeAddressFromReqisterQueue(address _address) internal {
        for (uint256 i = 0; i < registerQueue.length; i++) {
            if (registerQueue[i] == _address) {
                registerQueue[i] = registerQueue[registerQueue.length - 1];
                registerQueue.pop();break;
            }
        }
    }

    function getCouncilMemberAddresses() public view returns (address[] memory) {
        return councilMemberAddresses;
    }

    function getRegisterQueue() public view returns (address[] memory) {
        return registerQueue;
    }

    function getLockedWeightsRanking() public view returns (address[] memory) {
        return lockedWeightsRanking;
    }
    
    // ============ Proposal execute functions ============

    /**
        Apply to be council member
     */
    function applyCouncilMember(address addr) external {
        require(msg.sender == address(this), "FORBIDDEN");
        User storage user = users[addr];
        require(!user.isMerchant, "IS_MERCHANT");
        require(user.status == 1, "FORBIDDEN");
        require(user.lockedTokenAmount >= councilMemberMinimumLockAmount, "amount isn't enough");
        require(councilMemberAddresses.length < maximumCouncilMembers, "council members limit");
        for (uint i = 0; i < councilMemberAddresses.length; i++) {
            require(councilMemberAddresses[i] != addr, "already a council member");
        }
        user.isCouncilMember = true;
        councilMemberAddresses.push(addr);
    }

    /**
        Proposal to remove council member
     */
    function removeCouncilMember(address addr) external {
        require(msg.sender == address(this), "FORBIDDEN");
        User storage user = users[addr];
        user.isCouncilMember = false;
        for (uint i = 0; i < councilMemberAddresses.length; i++) {
            if (councilMemberAddresses[i] == addr) {
                councilMemberAddresses[i] = councilMemberAddresses[councilMemberAddresses.length - 1];
                councilMemberAddresses.pop();break;
            }
        }
    }
    

}