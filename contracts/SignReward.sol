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

    uint256 public signInterval = 10 seconds;
    uint256 public signRewardBaseAmount = 1 * 10 ** 18;

    mapping(address => SignRecord) public signRecords;
    address[] totalRewardsRanking;

    constructor (address _tokenAddress) {
        ESDToken = IBEP20(_tokenAddress);
    }

    function sign() public {
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
        updateTotalRewardsRanking(msg.sender);
    }

    function updateTotalRewardsRanking(address addr) internal {
        // check if exist
        bool inArr = false;
        for (uint i = 0; i < totalRewardsRanking.length; i++) {
            if (totalRewardsRanking[i] == addr) {
                inArr = true;
            }
        }
        if (!inArr) {
            totalRewardsRanking.push(addr);
        }
        uint256 llen = totalRewardsRanking.length;
        if (llen == 1) {
            return;
        }
        // sort
        address[] memory tmpArr = totalRewardsRanking;
        for (uint256 i = 0; i < llen - 1; i++) {
            for (uint256 j = 0; j < llen - 1 - i; j++) {
                address aa = tmpArr[j];
                address ab = tmpArr[j+1];
                if (signRecords[aa].totalRewards > signRecords[ab].totalRewards) {
                    tmpArr[j+1] = tmpArr[j];
                    tmpArr[j] = ab;
                }
            }
        }
        totalRewardsRanking = tmpArr;
        // slice
        if (llen > 10) {
            totalRewardsRanking.pop();
        }
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