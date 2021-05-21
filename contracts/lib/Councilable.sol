// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IEasydealCouncil.sol";

contract Councilable {

    IEasydealCouncil council;

    modifier viaCouncil() {
        require(msg.sender == address(council), "Easydeal: Forbidden");
        _;
    }

    constructor(address _councilContractAddress) {
        council = IEasydealCouncil(_councilContractAddress);
    }

    function updateCouncil(address _address) viaCouncil external {
        council = IEasydealCouncil(_address);
    }

    function getCouncilAddress() public view returns (address) {
        return address(council);
    }
}