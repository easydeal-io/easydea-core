// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import {IESDUser} from "./itf/IESDUser.sol";
import {IESDInfo} from "./itf/IESDInfo.sol";

/**
 * @title Easydeal Context
 * @author flex@easydeal.io
 *
 * @notice Other ESD contracts share states via this contract
 */

contract ESDContext {
    
    // ============ States ============
    address public ESDUserAddress;
    address public ESDInfoAddress;

    mapping(address => uint32[]) public userActiveInfoIds;
    mapping(address => uint32[]) public userActiveDealIds;

    modifier onlyUserContract() {
        require(msg.sender == ESDUserAddress, "FORBIDDEN");
        _;
    }

    modifier onlyInfoContract() {
        require(msg.sender == ESDInfoAddress, "FORBIDDEN");
        _;
    }

    constructor (address _userAddress, address _infoAddress) {
        ESDUserAddress = _userAddress;
        ESDInfoAddress = _infoAddress;
    }

    function isViaUserContract(address addr) external view returns (bool) {
        return addr == ESDUserAddress;
    }

    function isMerchant(address user) external view returns (bool) {
        return IESDUser(ESDUserAddress).isMerchant(user);
    }

    function isValidUser(address user) external view returns (bool) {
        return IESDUser(ESDUserAddress).isValidUser(user);
    }

    function isCouncilMember(address user) external view returns (bool) {
        return IESDUser(ESDUserAddress).isCouncilMember(user);
    }

    function computeLockedWeights(address user) external view returns (uint32) {
        return IESDUser(ESDUserAddress).computeLockedWeights(user);
    }

    function getActiveInfoIds(address user) external view returns (uint32[] memory) {
        return userActiveInfoIds[user];
    }

    function getActiveDealIds(address user) external view returns (uint32[] memory) {
        return userActiveDealIds[user];
    }

    function followSpace(uint32 id) external onlyUserContract {
        IESDInfo(ESDInfoAddress).followSpace(id);
    }

    function unfollowSpace(uint32 id) external onlyUserContract {
        IESDInfo(ESDInfoAddress).unfollowSpace(id);
    }

    function addActiveInfoId(address user, uint32 id) external onlyInfoContract {
        return userActiveInfoIds[user].push(id);
    }

    function addActiveDealId(address user, uint32 id) external onlyInfoContract {
        return userActiveDealIds[user].push(id);
    }

    function removeActiveInfoId(address user, uint32 id) external onlyInfoContract {
        uint32[] storage activeInfoIds = userActiveInfoIds[user];
        for (uint i = 0; i < activeInfoIds.length; i++) {
            if (activeInfoIds[i] == id) {
                activeInfoIds[i] = activeInfoIds[activeInfoIds.length - 1];
                activeInfoIds.pop();
            }
        } 
    }

    function removeActiveDealId(address user, uint32 id) external onlyInfoContract {
        uint32[] storage activeDealIds = userActiveDealIds[user];
        for (uint i = 0; i < activeDealIds.length; i++) {
            if (activeDealIds[i] == id) {
                activeDealIds[i] = activeDealIds[activeDealIds.length - 1];
                activeDealIds.pop();
            }
        } 
    }

}