// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

import {IBEP20} from "./itf/IBEP20.sol";

import {Info} from "./data/Info.sol";
import {Space} from "./data/Space.sol";
import {Deal} from "./data/Deal.sol";

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

    using Info for mapping(uint32 => Info.Data);
    using Space for mapping(uint32 => Space.Data);
    using Deal for mapping(uint32 => Deal.Data);

    // ============ States ============
    
    uint32 immutable MAX_PAGE_SIZE = 100;

    IBEP20 ESDToken;

    address public easydealAddress;
    uint32 public spaceCount = 0;
    uint32 public infoCount = 0;
    uint32 public dealCount = 0;

    mapping(uint32 => Info.Data) public infos;
    mapping(uint32 => Space.Data) public spaces;
    mapping(uint32 => Deal.Data) public deals;

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

        Space.Data storage space = spaces.get(spaceId);
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
        
        infos.add(
            ++infoCount,
            spaceId,
            iType,
            title,
            content,
            memo,
            msg.sender,
            price,
            qty,
            acceptToken
        );

        space.infos++;
    }

    function hideInfo(uint32 id) public {
        if (msg.sender != infos[id].owner || ESDContext.isMerchant(msg.sender)) {
            revert("FORBIDDEN");
        }
        infos.hide(id);
    }

    function makeDeal(uint32 infoId, uint qty) public payable {
        require(ESDContext.isValidUser(msg.sender), "FORBIDDEN");

        Info.Data storage info = infos.get(infoId);
        require(info.status == 1, "info status incorrect");
        require(ESDContext.isValidUser(info.owner), "info owner status incorrect");
        require(info.qty >= qty, "insufficient qty");

        Space.Data storage space = spaces.get(info.spaceId);
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

        deals.make(++dealCount, infoId, qty, msg.sender);

        info.qty--;
        space.deals++;
        
        if (info.qty == 0) {
            infos.hide(infoId);
        }
        _addActiveDeal(msg.sender, info.owner, dealCount);
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
        Deal.Data storage deal = deals.get(id);
        bool viaProposal = msg.sender == address(this);
        require(
            deal.status == 2 || (viaProposal && deal.status == 1),
            "deal status incorrect"
        );
        Info.Data memory info = infos[deal.infoId];

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
        deals.confirm(id);
        _removeActiveDeal(deal.maker, info.owner, id);
    }

    function cancelDeal(uint32 id) public {
        Deal.Data storage deal = deals.get(id);
        bool viaProposal = msg.sender == address(this);
        require(
            deal.status == 1 || (viaProposal && deal.status == 2),
            "deal status incorrect"
        );
        Info.Data memory info = infos[deal.infoId];

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
        deals.cancel(id);
        _removeActiveDeal(deal.maker, info.owner, id);
    }

    function followSpace(uint32 id) public {
        require(ESDContext.isValidUser(msg.sender), "FORBIDDEN");
        Space.Data storage space = spaces.get(id); 
        require(space.status == 1, "status incorrect");
        ESDContext.userFollowSpace(id);
        space.follows++;
    }

    function unfollowSpace(uint32 id) public {
        require(ESDContext.isValidUser(msg.sender), "FORBIDDEN");
        Space.Data storage space = spaces.get(id); 
        ESDContext.userUnfollowSpace(id);
        space.follows--;
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
        spaces.add(
            ++spaceCount,
            name,
            description,
            msg.sender,
            feeRate
        );
    }

    /**
        Hide space by creator
     */
    function hideSpace(uint32 id) public {
        require(ESDContext.isCouncilMember(msg.sender), "FORBIDDEN");
        spaces.hide(id);
    }

    function filterInfo(
        uint32[] memory spaceIds, 
        uint8[] memory status,
        address[] memory owners,
        uint32 page, 
        uint32 pageSize,
        bool desc
    ) public view returns(uint32[] memory, uint32) {
        if (pageSize > MAX_PAGE_SIZE) {
            pageSize = MAX_PAGE_SIZE;
        }
        return infos.filter(spaceIds, status, owners, page, pageSize, desc, infoCount);
    }

}