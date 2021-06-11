// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

import {SafeBEP20} from "./lib/SafeBEP20.sol";
import {SafeMath} from "./lib/SafeMath.sol";
import {Context} from "./lib/Context.sol";
import {IBEP20} from "./itf/IBEP20.sol";

contract SignReward is Context {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint256;

    IBEP20 ESDToken;

    struct SignRecord {
        uint256 lastSignedTimestamp;
        uint32 continuousNumber;
        uint256 totalRewards;
    }

    uint256 public signInterval = 10 minutes;
    uint256 public signRewardBaseAmount = 1 * 10 ** 18;

    mapping(address => SignRecord) public signRecords;
    address public easydealAddress;

    constructor (address _tokenAddress) {
        ESDToken = IBEP20(_tokenAddress);
    }

    function sign() public returns (bool) {
        require(ESDContext.isValidUser(msg.sender), "FORBIDDEN");
        
        uint32 lockedWeight = ESDContext.computeLockedWeights(msg.sender);
        SignRecord storage record = signRecords[msg.sender];
        require(block.timestamp > record.lastSignedTimestamp.add(signInterval), "ALREADY SIGNED");

        uint32 continuousNumber = record.continuousNumber;
        uint32 additionalTimes = continuousNumber / 30 + 1;
        uint256 rewardAmount = signRewardBaseAmount.mul(additionalTimes).mul(lockedWeight+1);

        // Reward token
        ESDToken.safeTransfer(msg.sender, rewardAmount);

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

    // ============ Proposal execute functions ============
    
    function updateSignInterval(uint32 interval) external {
        require(ESDContext.isViaUserContract(msg.sender), "FORBIDDEN");
        signInterval = interval;
    }

    function updateSignRewardBaseAmount(uint256 amount) external {
        require(ESDContext.isViaUserContract(msg.sender), "FORBIDDEN");
        signRewardBaseAmount = amount;
    }

}