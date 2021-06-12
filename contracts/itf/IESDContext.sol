// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

interface IESDContext {
    function isValidUser(address _address) external view returns(bool);
    function isMerchant(address _address) external view returns(bool);
    function isCouncilMember(address _address) external view returns(bool);
    function followSpace(uint32 id) external;
    function unfollowSpace(uint32 id) external;

    function computeLockedWeights(address _address) external view returns (uint32);

    function isViaUserContract(address addr) external view returns (bool);
    function getActiveDealIds(address user) external view returns (uint32[] memory);
    function getActiveInfoIds(address user) external view returns (uint32[] memory);

    function addActiveInfoId(address user, uint32 id) external;
    function addActiveDealId(address user, uint32 id) external;

    function removeActiveInfoId(address user, uint32 id) external;
    function removeActiveDealId(address user, uint32 id) external;
}