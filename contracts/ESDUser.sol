// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

import {IBEP20} from "./itf/IBEP20.sol";

import {User} from "./data/User.sol";
import {Proposal} from "./data/Proposal.sol";

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

    using User for mapping(address => User.Data);
    using Proposal for mapping(uint32 => Proposal.Data);

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

    mapping(address => User.Data) public users;
    mapping(uint32 => Proposal.Data) public proposals;

    // ============ Events ============

    receive() external payable {
    }

    // ============ Modifiers ============

    modifier onlyRegistered() {
        require(users.get(msg.sender).status == 1, "status incorrect");
        _;
    }

    modifier onlyMerchant() {
        require(
            users.get(msg.sender).status == 1 && users.get(msg.sender).isMerchant, 
            "satus incorrect"
        );
        _;
    }

    modifier onlyCouncilMember() {
        require(
            councilMemberAddresses.length == 0 || (
                users.get(msg.sender).status == 1 && users.get(msg.sender).isCouncilMember
            ), 
            "status incorrect"
        );
        _;
    }

    modifier verifyUser(address addr, uint8 status) {
        require(users.get(addr).timestamp > 0 && users.get(addr).status == status, "status incorrect");
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
        require(users.get(msg.sender).timestamp == 0, "exist");

        users.add(msg.sender, nickName, socialLink, bio);
        registerQueue.push(msg.sender);
    }

    function applyMerchant() public onlyRegistered {
        require(users.get(msg.sender).lockedTokenAmount >= merchantMinimumLockAmount, "locked amount not enough");
        users.toMerchant(msg.sender);
    }

    /**
        Guarantee an user by council member
     */
    function guaranteeUser(address addr) public onlyCouncilMember verifyUser(addr, 0) {
        users.gurantee(addr);
        _removeAddressFromReqisterQueue(addr);
    }

    /**
        Reject an user register by council member
     */
    function rejectUserRegister(address addr) public onlyCouncilMember {
        users.clear(addr);
        _removeAddressFromReqisterQueue(addr);
    }

    /**
        Ban an user register by council member
     */
    function banUser(address addr) public onlyCouncilMember {
        users.ban(addr);
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
        require(tipsAmount >= proposalTipsMinAmount, "tips not enough");

        uint tokenBalance = ESDToken.balanceOf(msg.sender);
        require(tokenBalance >= tipsAmount, "insufficient balance");
        ESDToken.safeTransferFrom(msg.sender, address(this), tipsAmount);

        proposals.add(
            ++proposalCount,
            msg.sender,
            tipsAmount,
            title,
            description,
            callData
        );

        haveReferendum[msg.sender] = true;
    }

    function voteOnProposal(uint32 pid, bool aye) public onlyRegistered {
       
        Proposal.Data storage proposal = proposals.get(pid);
        require(proposal.status == 1, "proposal isn't exist");

        uint attachedTokenAmount = proposal.tipsAmount.mul(votingAttachedTokenFactor).div(100);
        require(ESDToken.balanceOf(msg.sender) >= attachedTokenAmount, "insufficient balance");

        ESDToken.safeTransferFrom(msg.sender, address(this), attachedTokenAmount);
        
        proposals.vote(pid, aye, attachedTokenAmount);
        // voting deadline
        if (block.timestamp > (proposal.timestamp + proposalVotingDuration)) {
            
            haveReferendum[proposal.proposer] = false;
            uint averageAttachedTokenPerUser = proposal.naysAttachedTokenAmount.add(proposal.ayesAttachedTokenAmount);
            uint tipsPerUser = 0;

            if (proposal.ayes.length > proposal.nays.length) {
                // forward to council member seconds
                averageAttachedTokenPerUser = averageAttachedTokenPerUser.div(proposal.ayes.length);
                tipsPerUser = proposal.tipsAmount.div(proposal.ayes.length);

                for (uint i = 0; i < proposal.ayes.length; i++) {
                    ESDToken.safeTransfer(proposal.ayes[i], averageAttachedTokenPerUser.add(tipsPerUser));
                }

                proposal.status = 3;

            } else {
                // defeated
                averageAttachedTokenPerUser = averageAttachedTokenPerUser.div(proposal.nays.length);
                tipsPerUser = proposal.tipsAmount.div(proposal.nays.length);

                for (uint i = 0; i < proposal.nays.length; i++) {
                    ESDToken.safeTransfer(proposal.nays[i], averageAttachedTokenPerUser.add(tipsPerUser));
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
        Proposal.Data storage proposal = proposals.get(pid);
        uint32 numSeconds = proposals.second(pid);
        uint32 halfOfMembers = uint32(councilMemberAddresses.length)/2;
        if (numSeconds > halfOfMembers) {
            // execute
            (bool success, ) = address(this).call(proposal.callData);
            require(success, "execute failed");
            proposal.status = 4;
        }
    }

    function lockToken(uint256 amount) public onlyRegistered {
        require(amount > 0, "amount is zero");
        User.Data storage user = users.get(msg.sender);
        
        require(ESDToken.balanceOf(msg.sender) >= amount, "INSUFFICIENT_BALANCE");
        ESDToken.safeTransferFrom(msg.sender, address(this), amount);
        user.lockedTokenAmount += amount;
        totalLockedTokenAmount += amount;
        if (user.lockedBeginTimestamp == 0) {
            user.lockedBeginTimestamp = block.timestamp;
        }
    }

    function unlockToken(uint256 amount) public onlyRegistered {
        require(amount > 0, "amount is zero");
        User.Data storage user = users.get(msg.sender);
        require(user.lockedTokenAmount >= amount, "NOT_ENOUGH_LOCED");
        require(
            ESDContext.getActiveDealIds(msg.sender).length == 0 &&
            ESDContext.getActiveInfoIds(msg.sender).length == 0,
            "CAN_NOT_UNLOCK"
        );
        ESDToken.safeTransfer(msg.sender, amount);
        user.lockedTokenAmount -= amount;
        totalLockedTokenAmount -= amount;
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
    }

    // ============ Helper functions ============

    function isValidUser(address addr) public view returns (bool) {
        return users.get(addr).status == 1;
    }

    function isMerchant(address addr) public view returns (bool) {
        return users.get(addr).status == 1 && users.get(addr).isMerchant;
    }

    function isCouncilMember(address addr) public view returns (bool) {
        return users.get(addr).status == 1 && users.get(addr).isCouncilMember;
    }

    function userFollowSpace(uint32 id) external {
        users.followSpace(id);
    }

    function userUnfollowSpace(uint32 id) external {
        users.unfollowSpace(id);
    }

    function computeLockedWeights(address addr) public view returns (uint32) {
        return users.computeLockedWeights(addr, totalLockedTokenAmount, genesisBlockTimestamp);
    }

    function _removeAddressFromReqisterQueue(address _address) internal {
        for (uint256 i = 0; i < registerQueue.length; i++) {
            if (registerQueue[i] == _address) {
                registerQueue[i] = registerQueue[registerQueue.length - 1];
                registerQueue.pop();break;
            }
        }
    }

    function getCouncilMemberAddresses() public view returns(address[] memory) {
        return councilMemberAddresses;
    }

    function getRegisterQueue() public view returns(address[] memory) {
        return registerQueue;
    }
    
    // ============ Proposal execute functions ============

    /**
        Apply to be council member
     */
    function applyCouncilMember(address addr) external {
        require(msg.sender == address(this), "FORBIDDEN");
        User.Data storage user = users.get(addr);
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
        User.Data storage user = users.get(addr);
        user.isCouncilMember = false;
        for (uint i = 0; i < councilMemberAddresses.length; i++) {
            if (councilMemberAddresses[i] == addr) {
                councilMemberAddresses[i] = councilMemberAddresses[councilMemberAddresses.length - 1];
                councilMemberAddresses.pop();break;
            }
        }
    }
    

}