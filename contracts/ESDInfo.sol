// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

import {IBEP20} from "./itf/IBEP20.sol";

import {Context} from "./lib/Context.sol";
import {SafeBEP20} from "./lib/SafeBEP20.sol";
import {SafeMath} from "./lib/SafeMath.sol";

/**
 * @title Easydeal Info
 * @author flex@easydeal.io
 *
 */

contract ESDInfo is Context {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint256;

    // ============ Structs ============

    struct Info {
        uint32 id;
        uint32 spaceId;
        uint8 iType; // 0 sell, 1 buy
        string title;
        string content;
        string memo;
        address owner;
        uint256 price;
        uint256 qty;
        address acceptToken;
        uint256 timestamp;
        uint8 status; // 0 hide, 1 normal
    }

    struct Space {
        uint32 id;
        string name;
        string description;
        address creator;
        // deal fee rate for space creator
        uint32 feeRate;
        uint32 follows;
        uint32 infos;
        uint32 deals;
        uint256 timestamp;
        uint8 status; //  0 hide, 1 normal
    }

    struct Deal {
        uint32 id;
        uint32 infoId;
        uint256 qty;
        address maker;
        uint256 timestamp;
        uint8 status; // 0 canceled, 1 normal, 2 transferred 3 confirmed
    }

    // ============ Events ===========
    event InfoUpdated(uint32 id);
    event SpaceUpdated(uint32 id);
    event DealUpdated(uint32 id);

    // ============ States ============
    
    uint32 immutable MAX_PAGE_SIZE = 100;

    IBEP20 ESDToken;

    uint32 public spaceCount = 0;
    uint32 public infoCount = 0;
    uint32 public dealCount = 0;

    mapping(uint32 => Info) public infos;
    mapping(uint32 => Space) public spaces;
    mapping(uint32 => Deal) public deals;

    constructor (address _tokenAddress) {
        ESDToken = IBEP20(_tokenAddress);
    }

    function postInfo(
        uint32 spaceId, 
        uint8 iType,
        string memory title, 
        string memory content, 
        string memory memo,
        address acceptToken,
        uint256 qty,
        uint256 price
    ) public payable {
        require(ESDContext.isMerchant(msg.sender), "FORBIDDEN");

        require(price > 0, "INVALID_PRICE");
        require(qty > 0, "QTY_IS_ZERO");

        Space storage space = spaces[spaceId];
        require(space.status == 1, "SPACE_STATUS_INCORRECT");

        if (iType == 1) {
            if (acceptToken == address(0)) {
                require(msg.value == price * qty, "VALUE_IS_NOT_ENOUGH");
            } else {
                IBEP20 acceptTokenContract = IBEP20(acceptToken);
                require(acceptTokenContract.balanceOf(msg.sender) > price, "INSUFFICIENT_BALANCE");
                acceptTokenContract.safeTransferFrom(msg.sender, address(this), price * qty);
            }
        }
        infoCount++;
        infos[infoCount] = Info({
            id: infoCount,
            spaceId: spaceId,
            iType: iType,
            title: title,
            content: content,
            memo: memo,
            owner: msg.sender,
            price: price,
            qty: qty,
            acceptToken: acceptToken,
            timestamp: block.timestamp,
            status: 1
        });

        space.infos++;
    }

    function hideInfo(uint32 id) public {
        Info storage info = infos[id];
        if (msg.sender != info.owner || ESDContext.isCouncilMember(msg.sender)) {
            revert("FORBIDDEN");
        }
        info.status = 0;
        emit InfoUpdated(id);
    }

    function makeDeal(uint32 infoId, uint qty) public payable {
        require(
            ESDContext.isValidUser(msg.sender) &&
            !ESDContext.isCouncilMember(msg.sender), 
            "FORBIDDEN"
        );
        
        Info storage info = infos[infoId];
        require(info.status == 1, "info status incorrect");
        require(ESDContext.isValidUser(info.owner), "info owner status incorrect");
        require(info.qty >= qty, "insufficient qty");

        Space storage space = spaces[info.spaceId];
        require(space.status == 1, "space status is incorrect");

        if (info.iType == 0) {
            if (info.acceptToken == address(0)) {
                require(msg.value == info.price * qty, "value is not enough");
            } else {
                uint tokenBalance = ESDToken.balanceOf(msg.sender);
                require(tokenBalance >= info.price * qty, "insufficient balance");
                ESDToken.safeTransferFrom(msg.sender, address(this), info.price * qty);
            }
        }
        dealCount++;
        deals[dealCount] = Deal({
            id: dealCount,
            infoId: infoId,
            qty: qty,
            maker: msg.sender,
            timestamp: block.timestamp,
            status: 1
        });

        info.qty--;
        space.deals++;
        
        if (info.qty == 0) {
            info.status = 0;
        }
        _addActiveDeal(msg.sender, info.owner, dealCount);

        emit InfoUpdated(infoId);
    }

    function _addActiveDeal(address user1, address user2, uint32 dealId) private {
        ESDContext.addActiveDealId(user1, dealId);
        ESDContext.addActiveDealId(user2, dealId);
    }

    function _removeActiveDeal(address user1, address user2, uint32 dealId) private {
        ESDContext.removeActiveDealId(user1, dealId);
        ESDContext.removeActiveDealId(user2, dealId);
    }

    function confirmDeal(uint32 id) public {
        Deal storage deal = deals[id];
        bool viaProposal = msg.sender == address(this);
        require(
            deal.status == 2 || (viaProposal && deal.status == 1),
            "deal status incorrect"
        );
        Info memory info = infos[deal.infoId];

        address buyer = info.iType == 0 ? deal.maker : info.owner;
        address seller = info.iType == 0 ? info.owner : deal.maker;

        if (!viaProposal) {
            require(msg.sender == buyer, "FORBIDDEN");
        }

        if (info.acceptToken == address(0)) {
            payable(seller).transfer(info.price.mul(deal.qty));
        } else {
            IBEP20 token = IBEP20(info.acceptToken);
            token.transfer(seller, info.price.mul(deal.qty));
        }
        deal.status = 3;
        _removeActiveDeal(deal.maker, info.owner, id);

        emit DealUpdated(id);
    }

    function cancelDeal(uint32 id) public {
        Deal storage deal = deals[id];
        bool viaProposal = msg.sender == address(this);
        require(
            deal.status == 1 || (viaProposal && deal.status == 2),
            "deal status incorrect"
        );
        Info memory info = infos[deal.infoId];

        address buyer = info.iType == 0 ? deal.maker : info.owner;
        address seller = info.iType == 0 ? info.owner : deal.maker;

        if (!viaProposal) {
            require(msg.sender == buyer || msg.sender == seller, "FORBIDDEN");
        }
        // refunds
        if (info.acceptToken == address(0)) {
            payable(buyer).transfer(info.price.mul(deal.qty));
        } else {
            IBEP20 token = IBEP20(info.acceptToken);
            token.transfer(buyer, info.price.mul(deal.qty));
        }
        deal.status = 0;
        _removeActiveDeal(deal.maker, info.owner, id);

        emit DealUpdated(id);
    }

    function followSpace(uint32 id) external viaContext {
        Space storage space = spaces[id]; 
        require(space.status == 1, "status incorrect");
        space.follows++;

        emit SpaceUpdated(id);
    }

    function unfollowSpace(uint32 id) public viaContext {
        Space storage space = spaces[id]; 
        space.follows--;

        emit SpaceUpdated(id);
    }

    /**
        Add space by council member
     */
    function addSpace(
        string memory name, 
        string memory description, 
        uint32 feeRate
    ) public {
        require(ESDContext.isCouncilMember(msg.sender), "FORBIDDEN");
        require(feeRate <= 100, "feerate too high");
        spaceCount++;
        spaces[spaceCount] = Space({
            id: spaceCount,
            name: name,
            description: description,
            creator: msg.sender,
            feeRate: feeRate,
            follows: 0,
            infos: 0,
            deals: 0,
            timestamp: block.timestamp,
            status: 1
        });
    }

    /**
        Hide space by creator
     */
    function hideSpace(uint32 id) public {
        Space storage space = spaces[id];
        require(
            ESDContext.isCouncilMember(msg.sender) &&
            space.creator == msg.sender, 
            "FORBIDDEN"
        );
        space.status = 0;

        emit SpaceUpdated(id);
    }

}