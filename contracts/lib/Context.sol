// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import {IESDContext} from "../itf/IESDContext.sol";
import {IBEP20} from "../itf/IBEP20.sol";
import {SafeBEP20} from "./SafeBEP20.sol";

contract Context {
    using SafeBEP20 for IBEP20;

    uint256 public genesisBlock;
    IESDContext ESDContext;

    address owner;
    constructor() {
        owner = msg.sender;
        genesisBlock = block.number;
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

    function transferToken(address _token, uint256 amount, address dest) external {
        require(ESDContext.isViaUserContract(msg.sender), "FORBIDDEN");
        IBEP20 token = IBEP20(_token);
        token.safeTransfer(dest, amount);
    }

    function getContextAddress() public view returns (address) {
        return address(ESDContext);
    }
}