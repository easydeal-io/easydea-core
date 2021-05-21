// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./lib/Context.sol";
import "./lib/SafeBEP20.sol";

import "./interfaces/IBEP20.sol";
import "./interfaces/IEasydealUser.sol";
import "./interfaces/IEasydealInfo.sol";

contract EasydealCouncil is Context {

    using SafeMath for uint;
    using SafeBEP20 for IBEP20;

    // ============ Structs ============

    struct Member {
        string email;
        string website;
        uint lockedTokenAmount;
        uint32 blockTimestamp;
        uint8 status;
    }

    struct Proposal {
        address contractAddress;
        address proposer;
        uint tipAmount;
        uint32 expireTimestamp;
        uint32 blockTimestamp;
        uint ayesAttachedTokenAmount;
        uint naysAttachedTokenAmount;
        uint8 status; // 1 normal 2 fail 3 passed
        string description;
        bytes callData;
    }

    // ============ States ============

    address public tokenContractAddress;
    address public userContractAddress;
    address public infoContractAddress;
   
    uint public memberLockTokenMinAmount = 10000 * 10 ** 18;
    uint8 public maxMembers = 13;

    uint32 public proposalDuration = 1 seconds;

    uint public proposalTipMinAmount = 10 * 10 ** 18;

    // Vote attached tokens, percent of the proposal tip amount
    uint8 public voteAttachedTokenFactor = 10; 

    address[] _MEMBER_ADDRESSES;
    mapping(address => Member) public members;

    uint32 public proposalCount = 0;
    mapping(uint32 => Proposal) public proposals;
    mapping(address => bool) public proposing;

    mapping(uint32 => address[]) proposalAyes;
    mapping(uint32 => address[]) proposalNays;

    // ============ Modifiers ============

    modifier onlyMember() {
        require(members[_msgSender()].status == 1, "council member isn't exist or status is incorrect");
        _;
    }

    modifier viaCouncil() {
        require(_msgSender() == _address(), "Easydeal: FORBIDDEN");
        _;
    }

    constructor(address _tokenContractAddress) {
        // Init council
        members[_msgSender()] = Member({
            email: "",
            website: "",
            lockedTokenAmount: 0,
            blockTimestamp: _blockTimestamp(),
            status: 1
        });
        _MEMBER_ADDRESSES.push(_msgSender());

        tokenContractAddress = _tokenContractAddress;
    }
    
    /**
        Council member guarantee a register user
     */
    function guarantee(address user) public onlyMember returns (bool) {
        require(userContractAddress != address(0), "user contract address is not configured");
        IEasydealUser(userContractAddress).guarantee(user);
        return true;
    }

    /**
        Council member guarantee a register user
     */
    function rejectRegister(address user) public onlyMember returns (bool) {
        require(userContractAddress != address(0), "user contract address is not configured");
        IEasydealUser(userContractAddress).rejectRegister(user);
        return true;
    }

     /**
        Council member add a space
     */
    function addSpace(string memory name, string memory description, uint32 dealFeeRate) public onlyMember returns (bool) {
        require(infoContractAddress != address(0), "info contract address is not configured");
        IEasydealInfo(infoContractAddress).addSpace(name, description, dealFeeRate);

        return true;
    }

    /**
        Council member hide a space
     */
    function hideSpace(uint32 spaceId) public onlyMember returns (bool) {
        require(infoContractAddress != address(0), "info contract address is not configured");
        IEasydealInfo(infoContractAddress).hideSpace(spaceId);

        return true;
    }

    /**
        Council member update deal fee rate
     */
    function updateDealFeeRateForSpace(uint32 spaceId, uint32 rate) public onlyMember returns (bool) {
        require(infoContractAddress != address(0), "info contract address is not configured");
        IEasydealInfo(infoContractAddress).updateDealFeeRateForSpace(spaceId, rate);

        return true;
    }

    /**
        Submit a proposal

        NOTES:

        Each proposal need attach some tips for the voters
     */
    function submitProposal(
        address contractAddress,
        uint tipAmount, 
        string memory description,
        bytes calldata callData
    ) external returns (uint32) {
        if (members[_msgSender()].status != 1) {
            require(_msgSender() == userContractAddress, "Easydeal: FORBIDDEN");
        }

        require(!proposing[_txOrigin()], "you have a proposal");

        require(tipAmount >= proposalTipMinAmount, "tip amount is not enough");

        IBEP20 token = IBEP20(tokenContractAddress);
        uint tokenBalance = token.balanceOf(_txOrigin());

        require(tokenBalance >= tipAmount, "insufficient token balance for tip");

        token.safeTransferFrom(_txOrigin(), _address(), tipAmount);

        proposalCount += 1;
        proposals[proposalCount] = Proposal({
            contractAddress: contractAddress,
            proposer: _txOrigin(),
            tipAmount: tipAmount,
            expireTimestamp: _blockTimestamp() + proposalDuration,
            blockTimestamp: _blockTimestamp(),
            ayesAttachedTokenAmount: 0,
            naysAttachedTokenAmount: 0,
            status: 1,
            description: description,
            callData: callData
        });

        proposing[_txOrigin()] = true;

        return proposalCount;
    }

    /** 
        Vote for a proposal

        NOTES:

        Voter need attach some tokens, if his side winning, he will got the other side's tips,
        otherwise the opposite.
     */
    function voteProposal(uint32 pId, bool aye) external {
       
        if (members[_msgSender()].status != 1) {
            require(_msgSender() == userContractAddress, "Easydeal: FORBIDDEN");
        }

        Proposal storage proposal = proposals[pId];
        require(proposal.status == 1, "proposal isn't exist or status is incorrect");

        IBEP20 token = IBEP20(tokenContractAddress);
        uint attachedTokenAmount = proposal.tipAmount.mul(voteAttachedTokenFactor).div(100);

        require(token.balanceOf(_txOrigin()) >= attachedTokenAmount, "insufficient token balance for attached");

        address[] storage ayes = proposalAyes[pId];
        address[] storage nays = proposalNays[pId];

        for (uint i = 0; i < ayes.length; i++) {
            require(ayes[i] != _txOrigin(), "you have voted aye");
        }

        for (uint i = 0; i < nays.length; i++) {
            require(nays[i] != _txOrigin(), "you have voted nay");
        }

        token.safeTransferFrom(_txOrigin(), _address(), attachedTokenAmount);

        if (aye) {
            ayes.push(_txOrigin());
            proposal.ayesAttachedTokenAmount += attachedTokenAmount;
        } else {
            nays.push(_txOrigin());
            proposal.naysAttachedTokenAmount += attachedTokenAmount;
        }

        // voting deadline
        if (_blockTimestamp() > proposal.expireTimestamp) {
            
            proposing[proposal.proposer] = false;

            uint averageAttachedTokenPerUser = proposal.naysAttachedTokenAmount.add(proposal.ayesAttachedTokenAmount);
            uint tipsPerUser = 0;

            if (ayes.length > nays.length) {
                // aye side winning
                (bool success, ) = proposal.contractAddress.call(proposal.callData);
                require(success);
                
                averageAttachedTokenPerUser = averageAttachedTokenPerUser.div(ayes.length);
                tipsPerUser = proposal.tipAmount.div(ayes.length);

                for (uint i = 0; i < ayes.length; i++) {
                    token.safeTransfer(ayes[i], averageAttachedTokenPerUser.add(tipsPerUser));
                }

                proposal.status = 3;

            } else {
                // nay side winning
                
                averageAttachedTokenPerUser = averageAttachedTokenPerUser.div(nays.length);
                tipsPerUser = proposal.tipAmount.div(nays.length);

                for (uint i = 0; i < nays.length; i++) {
                    token.safeTransfer(nays[i], averageAttachedTokenPerUser.add(tipsPerUser));
                }

                proposal.status = 2;
            }
           
        }
    }

    function getMemberAddresses() public view returns (address[] memory) {
        return _MEMBER_ADDRESSES;
    }

    function getProposalAyes(uint32 pId) public view returns (address[] memory) {
        return proposalAyes[pId];
    }

    function getProposalNays(uint32 pId) public view returns (address[] memory) {
        return proposalNays[pId];
    }

    function _removeMemberAddress(address _address) internal {
        address[] memory addresses = _MEMBER_ADDRESSES;
        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == _address) {
                addresses[i] = addresses[addresses.length - 1];
                break;
            }
        }
        _MEMBER_ADDRESSES = addresses;
        _MEMBER_ADDRESSES.pop();
    }


    // ============ External Functions ============

    /**
        Proposal to add a council member
     */
    function addMember(address _address, string memory email, string memory website, uint lockTokenAmount) external viaCouncil {
        bool isValidUser = IEasydealUser(userContractAddress).isValidUser(_address);
        require(isValidUser, "user is not registered or status incorrect");
        require(uint8(_MEMBER_ADDRESSES.length) < maxMembers, "members count limit");

        require(lockTokenAmount >= memberLockTokenMinAmount, "lock amount is not enought");

        // lock token
        IBEP20 token = IBEP20(tokenContractAddress);
        uint tokenBalance = token.balanceOf(_address);

        require(tokenBalance >= lockTokenAmount, "insufficient token balance for lock");
        token.safeTransferFrom(_address, address(this), lockTokenAmount);

        members[_address] = Member({
            email: email,
            website: website,
            lockedTokenAmount: lockTokenAmount,
            blockTimestamp: _blockTimestamp(),
            status: 1
        });

        _MEMBER_ADDRESSES.push(_address);
    }

    /**
        Proposal to remove a council member
     */
    function removeMember(address _address) external viaCouncil {  
        Member memory member = members[_address];
        require(member.blockTimestamp > 0, "council member is not exist");
        
        delete members[_address];
        _removeMemberAddress(_address);

        IBEP20 token = IBEP20(tokenContractAddress);
        // refund token
        token.transfer(_address, member.lockedTokenAmount);

    }

    /**
        Proposal update user contract address
     */
    function updateUserContractAddress(address _address) external viaCouncil {
        userContractAddress = _address;
    }

    /**
        Proposal update info contract address
     */
    function updateInfoContractAddress(address _address) external viaCouncil {
        infoContractAddress = _address;
    }

    /**
        Update proposal tips min amount
     */
    function updateProposalTipMinAmount(uint amount) external viaCouncil {
        proposalTipMinAmount = amount;
    }

    /**
        Update vote attached token factor
     */
    function updateVoteAttachedTokenFactor(uint8 factor) external viaCouncil {
        voteAttachedTokenFactor = factor;
    }

    function updateProposalDuration(uint32 duration) external viaCouncil {
        proposalDuration = duration;
    }

}