// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

interface IESDInfo {
    function followSpace(uint32 id) external;
    function unfollowSpace(uint32 id) external;
}