// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./lib/Context.sol";
import "./lib/SafeMath.sol";
import "./lib/Ownable.sol";

import "./interfaces/IBEP20.sol";

contract SignReward is Context, Ownable {

    using SafeMath for uint;

    struct SignRecord {
        uint32 lastSignedTimestamp;
        uint32 continuousNumber;
    }

    uint32 public signInterval = 1 days;
    uint public signRewardAmount = 10 * 10 ** 18;

    mapping(address => SignRecord) public signRecords;

    address public userContractAddress;
    address public tokenContractAddress;

    constructor(address _userContractAddress, address _tokenContractAddress) {
        userContractAddress = _userContractAddress;
        tokenContractAddress = _tokenContractAddress;
    }

    function sign() external returns (bool) {
        require(_msgSender() == userContractAddress, "FORBIDDEN");

        SignRecord storage record = signRecords[_msgSender()];

        require(_blockTimestamp() > record.lastSignedTimestamp + signInterval, "ALREADY SIGNED");

        uint32 continuousNumber = record.continuousNumber;
       
        uint32 additionalPercent = continuousNumber / 10;
        if (additionalPercent > 100) {
            additionalPercent = 100;
        }

        uint rewardAmount = signRewardAmount.mul(100 + additionalPercent).div(100);

        // Reward token
        IBEP20 token = IBEP20(tokenContractAddress);
        token.transfer(_msgSender(), rewardAmount);

        // Interrupt continuation
        if (_blockTimestamp() > record.lastSignedTimestamp + 2*signInterval) {
            continuousNumber = 0;
        }

        signRecords[_msgSender()] = SignRecord({
            lastSignedTimestamp: _blockTimestamp(),
            continuousNumber: continuousNumber + 1
        });

        return true;
    }

    function updateSignInterval(uint32 interval) public onlyOwner {
        signInterval = interval;
    }

    function updateSignRewardAmount(uint amount) public onlyOwner {
        signRewardAmount = amount;
    }

}