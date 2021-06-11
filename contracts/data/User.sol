// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

import {SafeMath} from "./SafeMath.sol";

library User {
    using SafeMath for uint256;
    struct Data {
        string nickName;
        string socialLink;
        string bio;
        uint256 lockedBeginTimestamp;
        uint256 lockedTokenAmount;
        bool isMerchant;
        bool isCouncilMember;
        address guarantor;
        uint32[] followedSpaceIds;
        uint32 numFollowedSpaceIds;
        uint256 timestamp;
        uint8 status; // 0 wait for guarantee, 1 normal, 2 banned
    }

    function add(
        mapping(address => User.Data) storage self,
        address addr,
        string memory nickName,
        string memory socialLink,
        string memory bio
    ) internal {
        User.Data storage user = self[addr];
        user.nickName = nickName;
        user.socialLink = socialLink;
        user.bio = bio;
        user.lockedBeginTimestamp = 0;
        user.lockedTokenAmount = 0;
        user.isMerchant = false;
        user.isCouncilMember = false;
        user.guarantor = address(0);
        user.timestamp = block.timestamp;
        user.status = 0;
    }

    function get(
        mapping(address => User.Data) storage self,
        address addr
    ) internal view returns (User.Data storage user) {
        user = self[addr];
    }

    function toMerchant(
        mapping(address => User.Data) storage self,
        address addr
    ) internal {
       require(!self[addr].isCouncilMember, "you are council member");
       self[addr].isMerchant = true;
    }

    function clear(
        mapping(address => User.Data) storage self,
        address addr
    ) internal {
        require(self[addr].status == 0, "Denied");
        delete self[addr];
    }

    function ban(
        mapping(address => User.Data) storage self,
        address addr
    ) internal {
        require(self[addr].status == 1, "status incorrect");
        self[addr].status = 2;
    }

    function gurantee(
        mapping(address => User.Data) storage self,
        address addr
    ) internal {
        require(self[addr].status == 0, "status incorrect");
        self[addr].guarantor = msg.sender;
        self[addr].status = 1;
    }

    function followSpace(
        mapping(address => User.Data) storage self,
        uint32 id
    ) internal {
        User.Data storage user = self[tx.origin];
        for (uint i = 0; i < user.followedSpaceIds.length; i++) {
            if (user.followedSpaceIds[i] == id) {
                revert("already followed");
            }
        }
        user.followedSpaceIds.push(id);
        user.numFollowedSpaceIds++;
    }

    function unfollowSpace(
        mapping(address => User.Data) storage self,
        uint32 id
    ) internal {
        User.Data storage user = self[tx.origin];
        for (uint i = 0; i < user.followedSpaceIds.length; i++) {
            if (user.followedSpaceIds[i] == id) {
                user.followedSpaceIds[i] = user.followedSpaceIds[user.followedSpaceIds.length - 1];
                user.followedSpaceIds.pop();
                break;
            }
        }
        user.numFollowedSpaceIds--;
    }

    function computeLockedWeights(
        mapping(address => User.Data) storage self,
        address addr,
        uint256 totalLockedTokenAmount,
        uint256 genesisBlockTimestamp
    ) internal view returns (uint32) {
        User.Data memory user = self[addr];
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

}