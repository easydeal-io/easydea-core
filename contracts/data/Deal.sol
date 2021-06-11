// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

library Deal {
    struct Data {
        uint32 id;
        uint32 infoId;
        uint256 qty;
        address maker;
        uint256 timestamp;
        uint8 status; // 0 canceled, 1 normal, 2 transferred 3 confirmed
    }

    function make(
        mapping(uint32 => Deal.Data) storage self,
        uint32 id,
        uint32 infoId,
        uint256 qty,
        address maker
    ) internal {
        Deal.Data storage deal = self[id];
        deal.id = id;
        deal.infoId = infoId;
        deal.qty = qty;
        deal.maker = maker;
        deal.timestamp = block.timestamp;
        deal.status = 1;
    }

    function get(
        mapping(uint32 => Deal.Data) storage self,
        uint32 id
    ) internal view returns (Deal.Data storage deal) {
        deal = self[id];
    }

    function confirm(
        mapping(uint32 => Deal.Data) storage self,
        uint32 id
    ) internal {
       self[id].status = 3;
    }

    function cancel(
        mapping(uint32 => Deal.Data) storage self,
        uint32 id
    ) internal {
        self[id].status = 0;
    }

}