// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./lib/Context.sol";
import "./lib/SafeBEP20.sol";
import "./lib/Councilable.sol";

import "./interfaces/IBEP20.sol";
import "./interfaces/IEasydealInfo.sol";

contract EasydealUser is Context, Councilable {

    using SafeBEP20 for IBEP20;

    // ============ Structs ============

    struct User {
        string nickName;
        string email;
        string bio;
        uint32[] infoIds;
        uint32[] dealIds;
        uint guaranteeTipAmount;
        uint lockedTokenAmount;
        bool isMerchant;
        address guarantor;
        uint32 score;
        uint32 blockTimestamp;
        uint8 status; // 1 normal, 2 banned
    }

    // ============ States ============

    uint public merchantLockTokenMinAmount = 1000 * 10 ** 18;
    address[] _REGISTER_QUEUE;

    uint32 public registerQueueSize = 500;
    mapping(address => User) public users;

    /// Mapping of user to followed spaces
    mapping(address => uint32[]) followedSpaces;

    // ============ Modifiers ============

    modifier onlyRegistered() {
        require(users[_msgSender()].status == 1, "user is not registered or status is incorrect");
        _;
    }

    modifier onlyMerchant() {
        require(
            users[_msgSender()].status == 1 && users[_msgSender()].isMerchant, 
            "user is not merchant or status is incorrect"
        );
        _;
    }

    constructor(address _councilAddress) Councilable(_councilAddress) {}

    /**
        User register
        When a council member guarantee for him, he will get the tips
     */
    function register(string memory nickName, string memory email, string memory bio, uint guaranteeTipAmount) public returns(bool) {
        require(_REGISTER_QUEUE.length < registerQueueSize, "register queue size limit");
        require(users[_msgSender()].blockTimestamp == 0, "you are already in the register queue");

        if (guaranteeTipAmount > 0) {
            IBEP20 token = IBEP20(council.tokenContractAddress());

            uint256 tokenBalance = token.balanceOf(_msgSender());
            require(tokenBalance >= guaranteeTipAmount, "insufficient token balance for guarantee");

            token.safeTransferFrom(_msgSender(), _address(), guaranteeTipAmount);
        }

        users[_msgSender()] = User({
            nickName: nickName,
            email: email,
            bio: bio,
            infoIds: new uint32[](0),
            dealIds: new uint32[](0),
            guaranteeTipAmount: guaranteeTipAmount,
            lockedTokenAmount: 0,
            isMerchant: false,
            guarantor: address(0),
            score: 0,
            blockTimestamp: _blockTimestamp(),
            status: 0
        });

        _REGISTER_QUEUE.push(_msgSender());

        return true;
    }

    /**
        Each registered user can apply to be a merchant
        Need to lock some token, then they can post info
     */
    function applyMerchant(uint256 lockTokenAmount) public onlyRegistered returns (bool) {
        
        require(lockTokenAmount >= merchantLockTokenMinAmount, "lock token amount is not enough");

        User storage user = users[_msgSender()];

        require(!user.isMerchant, "you are already a merchant");

        IBEP20 token = IBEP20(council.tokenContractAddress());
        uint256 tokenBalance = token.balanceOf(_msgSender());
        require(tokenBalance >= lockTokenAmount, "insufficient token balance for lock");

        token.safeTransferFrom(_msgSender(), _address(), lockTokenAmount);

        user.isMerchant = true;
        user.lockedTokenAmount = lockTokenAmount;

        return true;
    }

    /**
        Each merchant can post info
     */
    function postInfo(
        uint32 spaceId, 
        uint8 iType,
        string memory title, 
        string memory content, 
        address acceptToken,
        uint256 price
    ) external payable onlyMerchant returns (uint32) {
        uint32 infoId = IEasydealInfo(council.infoContractAddress()).postInfo{value: msg.value}(
            spaceId, iType, title, content, acceptToken, price
        );
        
        users[_msgSender()].infoIds.push(infoId);

        return infoId;
    }

    /**
        User call another contract
     */
    function call(address target, bytes memory callData) public onlyRegistered returns (bytes memory) {
        (bool success, bytes memory result) = target.call(callData);
        require(success);
        
        return result;
    }

    function hideInfo(uint32 infoId) public onlyMerchant returns (bool) {
        IEasydealInfo(council.infoContractAddress()).hideInfo(infoId);

        return true;
    }

    function makeDeal(uint32 infoId) public onlyRegistered returns (uint32) {
        uint32 dealId = IEasydealInfo(council.infoContractAddress()).makeDeal(infoId);

        users[_msgSender()].dealIds.push(dealId);

        return dealId;
    }

    function confirmDeal(uint32 dealId) public onlyRegistered returns (bool) {
        IEasydealInfo(council.infoContractAddress()).confirmDeal(dealId);
        return true;
    }

    function cancelDeal(uint32 dealId) public onlyRegistered returns (bool) {
        IEasydealInfo(council.infoContractAddress()).cancelDeal(dealId);
        return true;
    }

    function followSpace(uint32 spaceId) public onlyRegistered returns (bool) {
        uint32[] storage spaceIds = followedSpaces[_msgSender()];
        for (uint i = 0; i < spaceIds.length; i++) {
            if (spaceIds[i] == spaceId) {
                return true;
            }
        }
        IEasydealInfo(council.infoContractAddress()).increaseSpaceFollows(spaceId);
        spaceIds.push(spaceId);
        return true;
    }

    function unFollowSpace(uint32 spaceId) public onlyRegistered returns (bool) {
        IEasydealInfo(council.infoContractAddress()).decreaseSpaceFollows(spaceId);
        uint32[] storage ids = followedSpaces[_msgSender()];
        bool changed = false;
        for (uint256 i = 0; i < ids.length; i++) {
            if (ids[i] == spaceId) {
                ids[i] = ids[ids.length - 1];
                changed = true;
                break;
            }
        }
        if (changed) {
            ids.pop();
        }
        return true;
    }

    /**
        Get the register queue, council member can guarantee for them
     */
    function getRegisterQueue() public view returns (address[] memory) {
        return _REGISTER_QUEUE;
    }

    function getFollowedSpaces(address user) public view returns (uint32[] memory) {
        return followedSpaces[user];
    }

    function _removeAddressFromRegisterQueue(address _address) internal {
        address[] memory addresses = _REGISTER_QUEUE;
        bool changed = false;
        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == _address) {
                addresses[i] = addresses[addresses.length - 1];
                changed = true;
                break;
            }
        }
        if (changed) {
            _REGISTER_QUEUE = addresses;
            _REGISTER_QUEUE.pop();
        }
    }


    // ============ External Functions ============

    function isValidUser(address _address) external view returns (bool) {
        return users[_address].status == 1;
    }

    /**
        A council member guarantee for an user
     */
    function guarantee(address _address) external viaCouncil {
        User storage user = users[_address];
        require(user.blockTimestamp > 0 && user.status == 0, "user is not registered or status is incorrect");

        if (user.guaranteeTipAmount > 0) {
            IBEP20 token = IBEP20(council.tokenContractAddress());
            token.safeTransfer(_txOrigin(), user.guaranteeTipAmount);
        }

        user.guarantor = _txOrigin();
        user.status = 1;

        _removeAddressFromRegisterQueue(_address);
    }

    /**
        A council member reject an user register, and remove the address from the queue
     */
    function rejectRegister(address _address) external viaCouncil {
        User storage user = users[_address];

        require(user.blockTimestamp > 0 && user.status == 0, "user is not registered or status is incorrect");
        if (user.guaranteeTipAmount > 0) {
            IBEP20 token = IBEP20(council.tokenContractAddress());
            token.safeTransfer(_address, user.guaranteeTipAmount);
        }

        _removeAddressFromRegisterQueue(_address);
        delete users[_address];
    }

    /**
        Proposal ban an user
     */
    function ban(address _address) external viaCouncil {
        User storage user = users[_address];
        require(user.blockTimestamp > 0 && user.status == 0, "user is not registered or status is incorrect");
        require(user.status != 2, "user was banned");

        user.status = 2;
    }

    /**
        Proposal compensate to someone
        For example, if someone suffers a loss in a trade, he can submit a proposal to get compensation
        If the proposal passed, he will get this compensation amount
     */
    function compensate(address from, address target, uint amount) external viaCouncil {
        User storage user = users[from];
        require(user.blockTimestamp > 0, "user is not registered");

        require(user.lockedTokenAmount >= amount, "the user's locked token is not enough");

        IBEP20 token = IBEP20(council.tokenContractAddress());
        token.safeTransfer(target, amount);

        user.lockedTokenAmount -= amount;

        // cancel merchant and refund locked token
        if (user.lockedTokenAmount < merchantLockTokenMinAmount) {
            user.isMerchant = false;
            if (user.lockedTokenAmount > 0) {
                token.safeTransfer(target, user.lockedTokenAmount);
            }
        }
    }

    function updateRegisterQueueSize(uint32 size) external viaCouncil {
        registerQueueSize = size;
    }

    function updateMerchantLockTokenMinAmount(uint amount) external viaCouncil {
        merchantLockTokenMinAmount = amount;
    }

}