// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IEasydealUser {
    function guarantee(address _address) external;
    function rejectRegister(address _address) external;

    function isValidUser(address _address) external returns (bool);

    function ban(address _address) external;

    function compensate(address from, address target, uint amount) external;
    
    function updateRegisterQueueSize(uint32 size) external;
    function updateMerchantLockTokenMinAmount(uint amount) external;
}