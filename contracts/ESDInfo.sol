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
        uint32 qty;
        uint32 pendingDeals;
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
        uint32 qty;
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
    event UserUpdated(address addr);
    event Notify(address indexed to, string message, uint maybeId);

    // ============ States ============
    
    uint32 immutable MAX_PAGE_SIZE = 100;

    IBEP20 ESDToken;

    uint32 public spaceCount = 0;
    uint32 private _infoId = 1;
    uint32 public infoCount = 0;
    uint32 public dealCount = 0;

    mapping(uint32 => Info) public infos;
    mapping(uint32 => Space) public spaces;
    mapping(uint32 => Deal) public deals;

    /// deal fee rate per thousand
    uint32 public dealFeeRate = 2;


    modifier onlyProposal() {
        require(ESDContext.isViaUserContract(msg.sender), "FORBIDDEN");
        _;
    }

    constructor (address _tokenAddress) {
        ESDToken = IBEP20(_tokenAddress);
    }

    function postInfo(
        uint32 spaceId, 
        uint8 iType,
        string memory title, 
        string memory content, 
        address acceptToken,
        uint32 qty,
        uint256 price
    ) public payable {
        require(ESDContext.isMerchant(msg.sender), "FORBIDDEN");

        require(price > 0, "INVALID_PRICE");
        require(qty > 0, "QTY_IS_ZERO");

        Space storage space = spaces[spaceId];
        require(space.status == 1, "SPACE_STATUS_INCORRECT");

        if (iType == 1) {
            if (acceptToken == address(0)) {
                require(msg.value == price.mul(qty), "VALUE_IS_NOT_ENOUGH");
            } else {
                IBEP20 acceptTokenContract = IBEP20(acceptToken);
                uint256 amount = price.mul(qty);
                require(acceptTokenContract.balanceOf(msg.sender) >= amount, "INSUFFICIENT_BALANCE");
                acceptTokenContract.safeTransferFrom(msg.sender, address(this), amount);
            }
        }
        
        infos[_infoId] = Info({
            id: _infoId,
            spaceId: spaceId,
            iType: iType,
            title: title,
            content: content,
            owner: msg.sender,
            price: price,
            qty: qty,
            pendingDeals: 0,
            acceptToken: acceptToken,
            timestamp: block.timestamp,
            status: 1
        });
        
        emit InfoUpdated(_infoId);
        emit SpaceUpdated(spaceId);

        _infoId++;
        infoCount++;
        space.infos++;
    }

    /**
        Remove info by owner
     */
    function removeInfo(uint32 id) public {
        Info storage info = infos[id];
        require(msg.sender == info.owner, "FORBIDDEN");
        require(info.status == 0, "STATUS_INCORRECT");
        require(info.pendingDeals == 0, "HAVE_PENDING_DEALS");

        Space storage space = spaces[info.spaceId];

        // refund
        if (info.iType == 1 && info.qty > 0) {
            uint256 totalAmount = info.price.mul(info.qty);
            if (info.acceptToken == address(0)) {
                payable(info.owner).transfer(totalAmount);
            } else {
                IBEP20 token = IBEP20(info.acceptToken);
                token.transfer(info.owner, totalAmount);
                emit UserUpdated(info.owner);
            }
        }
        
        delete infos[id];

        emit InfoUpdated(id);
        emit SpaceUpdated(space.id);

        infoCount--;
        space.infos--;
    }

    /**
        Hide info by owner or proposal
     */
    function hideInfo(uint32 id) external {
        Info storage info = infos[id];
        require(
            msg.sender == info.owner || 
            ESDContext.isViaUserContract(msg.sender),
            "FORBIDDEN"
        );

        info.status = 0;
        emit InfoUpdated(id);
    }

    function makeDeal(uint32 infoId, uint32 qty, string memory memo) public payable {
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
                emit UserUpdated(msg.sender);
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
        info.pendingDeals += 1;
        space.deals++;
       
        _addActiveDeal(msg.sender, info.owner, dealCount);

        emit InfoUpdated(infoId);
        emit DealUpdated(dealCount);
        emit SpaceUpdated(info.spaceId);
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
        bool viaProposal = ESDContext.isViaUserContract(msg.sender);
        require(
            deal.status == 2 || (viaProposal && deal.status == 1),
            "deal status incorrect"
        );
        Info storage info = infos[deal.infoId];
        Space memory space = spaces[info.spaceId];

        if (!viaProposal) {
            require(msg.sender == deal.buyer, "FORBIDDEN");
        }
        uint totalAmount = info.price.mul(deal.qty);
        if (info.acceptToken == address(0)) {
            // transfer to space creator
            if (space.feeRate > 0) {
                payable(space.creator).transfer(totalAmount.mul(space.feeRate).div(1000));
            }
            // transfer to seller
            payable(deal.seller).transfer(totalAmount.mul(1000 - dealFeeRate - space.feeRate).div(1000));
        } else {
            IBEP20 token = IBEP20(info.acceptToken);
            // transfer to space creator
            if (space.feeRate > 0) {
                token.transfer(space.creator, totalAmount.mul(space.feeRate).div(1000));
            }
            // transfer to seller
            token.transfer(deal.seller, totalAmount.mul(1000 - dealFeeRate - space.feeRate).div(1000));
            emit UserUpdated(deal.seller);
            emit UserUpdated(space.creator);
        }

        info.pendingDeals -= 1;

        deal.status = 3;
        _removeActiveDeal(deal.buyer, deal.seller, id);

        emit DealUpdated(id);
        emit InfoUpdated(info.id);
        emit Notify(deal.seller, "DEAL_CONFIRM", id);
    }

    function cancelDeal(uint32 id) public {
        Deal storage deal = deals[id];
        bool viaProposal = ESDContext.isViaUserContract(msg.sender);
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
            emit UserUpdated(deal.buyer);
        }

        deal.status = 0;
        info.qty += deal.qty;
        info.pendingDeals -= 1;

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
        emit SpaceUpdated(spaceCount);
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

    /**
        Show space by creator
     */
    function showSpace(uint32 id) public {
        Space storage space = spaces[id];
        require(
            ESDContext.isCouncilMember(msg.sender) &&
            space.creator == msg.sender, 
            "FORBIDDEN"
        );
        space.status = 1;

        emit SpaceUpdated(id);
    }

    /**
        Update space
     */
    function updateSpace(
        uint32 id,
        string memory name,
        string memory description,
        uint32 feeRate
    ) public {
        Space storage space = spaces[id];
        require(
            ESDContext.isCouncilMember(msg.sender) &&
            space.creator == msg.sender, 
            "FORBIDDEN"
        );
        require(feeRate <= 100, "FEE_RATE_TOO_HIGH");
        
        space.name = name;
        space.description = description;
        space.feeRate = feeRate;

        emit SpaceUpdated(id);
    }

    /**
        Configs
     */

    function updateDealFeeRate(uint32 feeRate) external onlyProposal{
        dealFeeRate = feeRate;
    }
}