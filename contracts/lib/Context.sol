// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import {IESDContext} from "../itf/IESDContext.sol";

contract Context {
    IESDContext ESDContext;

    address owner;
    
    constructor() {
        owner = msg.sender;
    }

    modifier viaContext() {
        require(msg.sender == address(ESDContext), "FORBIDDEN");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "FORBIDDEN");
        _;
    }

    function updateContext(address _contextAddress) public onlyOwner {
        ESDContext = IESDContext(_contextAddress);
    }

    function getContextAddress() public view returns (address) {
        return address(ESDContext);
    }
}