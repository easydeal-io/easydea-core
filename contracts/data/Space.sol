// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

library Space {
    struct Data {
        uint32 id;
        string name;
        string description;
        address creator;
        // deal fee rate for space creator
        uint32 feeRate;
        uint32 follows;
        uint32 infos;
        uint32 deals;
        uint256 timestamp;
        uint8 status; //  0 hide, 1 normal
    }

    function add(
        mapping(uint32 => Space.Data) storage self,
        uint32 id,
        string memory name,
        string memory description,
        address creator,
        uint32 feeRate
    ) internal {
        Space.Data storage space = self[id];
        space.id = id;
        space.name = name;
        space.description = description;
        space.creator = creator;
        space.feeRate = feeRate;
        space.follows = 0;
        space.infos = 0;
        space.deals = 0;
        space.timestamp = block.timestamp;
        space.status = 1;
    }

    function get(
        mapping(uint32 => Space.Data) storage self,
        uint32 id
    ) internal view returns (Space.Data storage space) {
        space = self[id];
    }

    function hide(
        mapping(uint32 => Space.Data) storage self,
        uint32 id
    ) internal {
        require(tx.origin == self[id].creator, "Easydeal: FORBIDDEN");
        self[id].status = 0;
    }

}