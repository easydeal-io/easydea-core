// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

interface IEasydeal {
    function isValidUser(address _address) external view returns(bool);
    function computeLockedWeights(address _address) external view returns (uint32);
}