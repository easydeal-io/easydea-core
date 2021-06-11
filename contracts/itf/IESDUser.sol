// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

interface IESDUser {
    function isValidUser(address _address) external view returns(bool);
    function isMerchant(address _address) external view returns(bool);
    function isCouncilMember(address _address) external view returns(bool);
    function userFollowSpace(uint32 id) external;
    function userUnfollowSpace(uint32 id) external;

    function computeLockedWeights(address _address) external view returns (uint32);
}