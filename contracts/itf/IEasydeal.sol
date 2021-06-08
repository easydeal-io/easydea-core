// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

interface IEasydeal {
    function computeLockedWeight(address _address) external view returns (uint256);
}