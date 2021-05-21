// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IEasydealCouncil {
    function memberLockTokenMinAmount() external view returns (uint);

    function submitProposal(
        address proposer,
        address contractAddress,
        bytes calldata callData, 
        uint tipAmount, 
        string memory description
    ) external returns (uint32);

    function tokenContractAddress() external view returns (address);
    function infoContractAddress() external view returns (address);
    function userContractAddress() external view returns (address);
  
}