// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IEasydealInfo {
    function postInfo(
        uint32 spaceId, 
        uint8 iType,
        string memory title, 
        string memory content, 
        address acceptToken,
        uint256 price
    ) external payable returns (uint32);

    function hideInfo(uint32 infoId) external;

    function makeDeal(uint32 infoId) external returns (uint32);
    function confirmDeal(uint32 dealId) external;
    function cancelDeal(uint32 dealId) external;

    function addSpace(string memory name, string memory description, uint32 dealFeeRate) external;
    function hideSpace(uint32 spaceId) external;

    function increaseSpaceFollows(uint32 spaceId) external;
    function decreaseSpaceFollows(uint32 spaceId) external; 

    function updateDealFeeRateForSpace(uint32 spaceId, uint32 rate) external;
}