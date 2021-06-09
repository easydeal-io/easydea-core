// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

import {SafeMath} from "./lib/SafeMath.sol";
import {Ownable} from "./lib/Ownable.sol";

import {IBEP20} from "./itf/IBEP20.sol";
import {IEasydeal} from "./itf/IEasydeal.sol";

contract SignReward is Ownable {

    using SafeMath for uint256;

    struct SignRecord {
        uint256 lastSignedTimestamp;
        uint32 continuousNumber;
        uint256 totalRewards;
    }

    uint256 public signInterval = 1 hours;
    uint256 public signRewardBaseAmount = 1 * 10 ** 18;

    mapping(address => SignRecord) public signRecords;

    address public easydealAddress;
    address public esdTokenAddress;

    constructor(address _easydealAddress, address _esdTokenAddress) {
        easydealAddress = _easydealAddress;
        esdTokenAddress = _esdTokenAddress;
    }

    function sign() public returns (bool) {
        IEasydeal easydeal = IEasydeal(easydealAddress);
        require(easydeal.isValidUser(msg.sender), "FORBIDDEN");
        
        uint32 lockedWeight = easydeal.computeLockedWeights(msg.sender);
        SignRecord storage record = signRecords[msg.sender];
        require(block.timestamp > record.lastSignedTimestamp.add(signInterval), "ALREADY SIGNED");

        uint32 continuousNumber = record.continuousNumber;
        uint32 additionalTimes = continuousNumber / 30 + 1;
        uint256 rewardAmount = signRewardBaseAmount.mul(additionalTimes).mul(lockedWeight+1);

        // Reward token
        IBEP20 token = IBEP20(esdTokenAddress);
        token.transfer(msg.sender, rewardAmount);

        // Interrupt continuation
        if (block.timestamp > record.lastSignedTimestamp + 2*signInterval) {
            continuousNumber = 1;
        } else {
            continuousNumber += 1;
        }

        record.continuousNumber = continuousNumber;
        record.lastSignedTimestamp = block.timestamp;
        record.totalRewards += rewardAmount;
       
        return true;
    }

    function updateSignInterval(uint32 interval) public onlyOwner {
        signInterval = interval;
    }

    function updateSignRewardBaseAmount(uint256 amount) public onlyOwner {
        signRewardBaseAmount = amount;
    }

}