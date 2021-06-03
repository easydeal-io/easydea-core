// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

import {SafeMath} from "./lib/SafeMath.sol";
import {Ownable} from "./lib/Ownable.sol";

import {IBEP20} from "./itf/IBEP20.sol";

contract SignReward is Ownable {

    using SafeMath for uint256;

    struct SignRecord {
        uint256 lastSignedTimestamp;
        uint32 continuousNumber;
    }

    uint32 public signInterval = 1 days;
    uint256 public signRewardAmount = 10 * 10 ** 18;

    mapping(address => SignRecord) public signRecords;

    address public easydealAddress;
    address public esdTokenAddress;

    constructor(address _easydealAddress, address _esdTokenAddress) {
        easydealAddress = _easydealAddress;
        esdTokenAddress = _esdTokenAddress;
    }

    function sign() external returns (bool) {
        require(msg.sender == easydealAddress, "FORBIDDEN");

        SignRecord storage record = signRecords[msg.sender];
        require(block.timestamp > record.lastSignedTimestamp + signInterval, "ALREADY SIGNED");

        uint32 continuousNumber = record.continuousNumber;
       
        uint32 additionalPercent = continuousNumber / 10;
        if (additionalPercent > 100) {
            additionalPercent = 100;
        }

        uint rewardAmount = signRewardAmount.mul(100 + additionalPercent).div(100);

        // Reward token
        IBEP20 token = IBEP20(esdTokenAddress);
        token.transfer(msg.sender, rewardAmount);

        // Interrupt continuation
        if (block.timestamp > record.lastSignedTimestamp + 2*signInterval) {
            continuousNumber = 0;
        }

        signRecords[msg.sender] = SignRecord({
            lastSignedTimestamp: block.timestamp,
            continuousNumber: continuousNumber + 1
        });

        return true;
    }

    function updateSignInterval(uint32 interval) public onlyOwner {
        signInterval = interval;
    }

    function updateSignRewardAmount(uint256 amount) public onlyOwner {
        signRewardAmount = amount;
    }

}