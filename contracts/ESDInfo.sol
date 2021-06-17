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
        address buyer;
        address seller;
        string memo;
        string transferInfo;
        uint256 timestamp;
        uint8 status; // 0 canceled, 1 placed, 2 transferred 3 confirmed
    }

    // ============ Events ===========
    event InfoUpdated(uint32 id);
    event SpaceUpdated(uint32 id);
    event DealUpdated(uint32 id);
    event Notify(address indexed to, string message, uint maybeId);

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
                uint256 amount = price.mul(qty);
                require(acceptTokenContract.balanceOf(msg.sender) >= amount, "INSUFFICIENT_BALANCE");
                acceptTokenContract.safeTransferFrom(msg.sender, address(this), amount);
            }
        }
        infoCount++;
        infos[infoCount] = Info({
            id: infoCount,
            spaceId: spaceId,
            iType: iType,
            title: title,
            content: content,
            owner: msg.sender,
            price: price,
            qty: qty,
            acceptToken: acceptToken,
            timestamp: block.timestamp,
            status: 1
        });

        space.infos++;
    }

    function showInfo(uint32 id) public {
        Info storage info = infos[id];
        require(
            ESDContext.isValidUser(msg.sender) &&
            msg.sender == info.owner, 
            "FORBIDDEN"
        );
        require(info.qty > 0, "QTY IS ZERO");
        info.status = 1;
        emit InfoUpdated(id);
    }

    function hideInfo(uint32 id) external {
        Info storage info = infos[id];
        if (
            msg.sender == info.owner || 
            ESDContext.isCouncilMember(msg.sender) ||
            ESDContext.isViaUserContract(msg.sender)
        ) {
            info.status = 0;
            emit InfoUpdated(id);
        } else {
            revert("FORBIDDEN");
        }
    }

    function makeDeal(uint32 infoId, uint qty, string memory memo) public payable {
        require(
            ESDContext.isValidUser(msg.sender) &&
            !ESDContext.isCouncilMember(msg.sender), 
            "FORBIDDEN"
        );
        
        Info storage info = infos[infoId];
        require(msg.sender != info.owner, "CAN_NOT_BUY_YOURSELF");
        require(info.status == 1, "INFO_STATUS_INCORRECT");
        require(ESDContext.isValidUser(info.owner), "OWNER_INVALID");
        require(info.qty >= qty, "INSUFFICIENT QTY");

        Space storage space = spaces[info.spaceId];
        require(space.status == 1, "SPACE_STATUS_INCORRECT");

        if (info.iType == 0) {
            if (info.acceptToken == address(0)) {
                require(msg.value == info.price.mul(qty), "VALUE_NOT_ENOUGH");
            } else {
                IBEP20 acceptTokenContract = IBEP20(info.acceptToken);
                uint256 amount = info.price.mul(qty);
                require(acceptTokenContract.balanceOf(msg.sender) >= amount, "INSUFFICIENT_BALANCE");
                acceptTokenContract.safeTransferFrom(msg.sender, address(this), amount);
            }
        }
        dealCount++;
        deals[dealCount] = Deal({
            id: dealCount,
            infoId: infoId,
            qty: qty,
            buyer: info.iType == 0 ? msg.sender : info.owner,
            seller: info.iType == 0 ? info.owner : msg.sender,
            memo: memo,
            transferInfo: "",
            timestamp: block.timestamp,
            status: 1
        });

        info.qty -= qty;
        space.deals++;
        
        if (info.qty == 0) {
            info.status = 0;
        }
        _addActiveDeal(msg.sender, info.owner, dealCount);

        emit InfoUpdated(infoId);
        emit Notify(info.owner, "DEAL_NEW", dealCount);
    }

    function updateDealMemo(uint32 id, string memory memo) public {
        Deal storage deal = deals[id];
        require(msg.sender == deal.buyer, "FORBIDDEN");
        require(deal.status == 1, "STATUS_INCORRECT");
        deal.memo = memo;
        emit DealUpdated(id);
        emit Notify(deal.seller, "DEAL_MEMO", id);
    }

    function transferDeal(uint32 id, string memory transferInfo) public {
        Deal storage deal = deals[id];
        require(msg.sender == deal.seller, "FORBIDDEN");
        deal.transferInfo = transferInfo;
        deal.status = 2;
        emit DealUpdated(id);
        emit Notify(deal.buyer, "DEAL_TRANSFER", id);
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

        if (!viaProposal) {
            require(msg.sender == deal.buyer, "FORBIDDEN");
        }

        if (info.acceptToken == address(0)) {
            payable(deal.seller).transfer(info.price.mul(deal.qty));
        } else {
            IBEP20 token = IBEP20(info.acceptToken);
            token.transfer(deal.seller, info.price.mul(deal.qty));
        }
        deal.status = 3;
        _removeActiveDeal(deal.buyer, deal.seller, id);

        emit DealUpdated(id);
        emit Notify(deal.seller, "DEAL_CONFIRM", id);
    }

    function cancelDeal(uint32 id) public {
        Deal storage deal = deals[id];
        bool viaProposal = msg.sender == address(this);
        require(
            deal.status == 1 || (viaProposal && deal.status == 2),
            "deal status incorrect"
        );
        Info storage info = infos[deal.infoId];

        if (!viaProposal) {
            require(
                msg.sender == deal.buyer || msg.sender == deal.seller, 
                "FORBIDDEN"
            );
        }
        // refunds
        if (info.acceptToken == address(0)) {
            payable(deal.buyer).transfer(info.price.mul(deal.qty));
        } else {
            IBEP20 token = IBEP20(info.acceptToken);
            token.transfer(deal.buyer, info.price.mul(deal.qty));
        }
        deal.status = 0;
        info.qty += deal.qty;
        info.status = 1;
        _removeActiveDeal(deal.buyer, deal.seller, id);
        emit DealUpdated(id);
        emit InfoUpdated(info.id);
        emit Notify(msg.sender == deal.buyer ? deal.seller : deal.buyer, "DEAL_CANCEL", id);
    }

    function followSpace(uint32 id) external viaContext {
        Space storage space = spaces[id]; 
        require(space.status == 1, "status incorrect");
        space.follows++;

        emit SpaceUpdated(id);
    }

    function unfollowSpace(uint32 id) public viaContext {
        Space storage space = spaces[id]; 
        if (space.follows > 0) {
            space.follows--;
        }
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