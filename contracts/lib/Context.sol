// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import {IESDContext} from "../itf/IESDContext.sol";

contract Context {
    IESDContext ESDContext;

    function updateContext(address _contextAddress) external {
        require(ESDContext.isViaUserContract(msg.sender), "FORBIDDEN");
        ESDContext = IESDContext(_contextAddress);
    }

    function getContextAddress() public view returns (address) {
        return address(ESDContext);
    }
}