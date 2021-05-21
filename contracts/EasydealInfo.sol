// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./lib/Context.sol";
import "./lib/Councilable.sol";
import "./lib/SafeBEP20.sol";
import "./lib/SafeMath.sol";

contract EasydealInfo is Context, Councilable {
    
    using SafeBEP20 for IBEP20;
    using SafeMath for uint256;

    // ============ Structs ============

    struct Space {
        string name;
        string description;
        address creator;
        // deal fee rate for space creator
        uint32 dealFeeRate;
        uint32 follows;
        uint32 totalInfos;
        uint32 totalDeals;
        uint32 blockTimestamp;
        uint8 status; //  0 hide 1 normal
    }

    struct Info {
        uint8 iType; // 0 sell 1 buy
        string title;
        string content;
        address owner;
        uint256 price;
        address acceptToken;
        uint32 deals;
        uint32 spaceId;
        uint32 blockTimestamp;
        uint8 status; // 0 hide 1 normal
    }

    struct Deal {
        uint32 infoId;
        address maker;
        uint32 blockTimestamp;
        uint8 status; // 0 canceled 1 normal 2 confirmed
    }

    // ============ States ============

    uint32 constant MAX_PAGE_SIZE = 100;

    /// deal fee rate per thousand, for platform
    uint32 public globalDealFeeRate = 2;
   
    uint32 public infoCount = 0;
    mapping(uint32 => Info) public infos;

    uint32 public spaceCount = 0;
    mapping(uint32 => Space) public spaces;

    uint32 public dealCount = 0;
    mapping(uint32 => Deal) public deals;

    // ============ Events ============

    event PostInfo(uint32 spaceId, address indexed owner, string title, string content, uint256 price);
    event MakeDeal(uint32 infoId, address indexed maker);

    constructor(address _councilAddress) Councilable(_councilAddress) {}

    // ============ External Functions ============

    function postInfo(
        uint32 spaceId, 
        uint8 iType,
        string memory title, 
        string memory content, 
        address acceptToken,
        uint256 price
    ) external payable returns (uint32) {
        require(_msgSender() == council.userContractAddress(), "Easydeal: FORBIDDEN");

        require(price > 0, "invalid price");

        Space memory space = spaces[spaceId];
        require(space.status == 1, "space isn't exist or status is incorrect");

        if (iType == 1) {
            if (acceptToken == address(0)) {
                require(msg.value == price, "deposit value is not enough");
            } else {
                IBEP20 acceptTokenContract = IBEP20(acceptToken);
                require(acceptTokenContract.balanceOf(_txOrigin()) > price, "insufficient balance to deposit");
                acceptTokenContract.safeTransferFrom(_txOrigin(), _address(), price);
            }
            
        }
        infoCount++;
        infos[infoCount] = Info({
            iType: iType,
            title: title,
            content: content,
            owner: _txOrigin(),
            price: price,
            acceptToken: acceptToken,
            deals: 0,
            spaceId: spaceId,
            blockTimestamp: _blockTimestamp(),
            status: 1
        });

        space.totalInfos++;
        
        emit PostInfo(spaceId, _txOrigin(), title, content, price);

        return infoCount;
    }

    function hideInfo(uint32 infoId) external {
        
        Info storage info = infos[infoId];
        require(info.status == 1, "info isn't exist or status is incorrect");

        if (_msgSender() != address(council)) {
            if (_msgSender() == council.userContractAddress()) {
                require(_txOrigin() == info.owner, "you aren't the info owner");
            } else {
                revert("Esaydeal: FORBIDDEN");
            }
        }

        info.status = 2;
    }

    function makeDeal(uint32 infoId) external returns (uint32) {
        require(_msgSender() == council.userContractAddress(), "Easydeal: FORBIDDEN");

        Info storage info = infos[infoId];
        require(info.status == 1, "info isn't exist or status is incorrect");

        Space memory space = spaces[info.spaceId];
        require(space.status == 1, "space status is incorrect");

        IBEP20 token = IBEP20(council.tokenContractAddress());
        uint tokenBalance = token.balanceOf(_txOrigin());

        require(tokenBalance >= info.price, "insufficient balance to make deal");
        token.safeTransferFrom(_txOrigin(), _address(), info.price);

        deals[dealCount++] = Deal({
            infoId: infoId,
            maker: _txOrigin(),
            blockTimestamp: _blockTimestamp(),
            status: 1
        });

        info.deals++;

        space.totalDeals++;

        emit MakeDeal(infoId, _txOrigin());

        return dealCount;
    }

    function confirmDeal(uint32 dealId) external {

        Deal storage deal = deals[dealId];
        require(deal.status == 1, "deal is not exist or status incorrect");

        if (_msgSender() != address(council)) {
            if (_msgSender() == council.userContractAddress()) {
                require(_txOrigin() == deal.maker, "you aren't the deal maker");
            } else {
                revert("Esaydeal: FORBIDDEN");
            }
        }

        Info memory info = infos[deal.infoId];
        Space memory space = spaces[info.spaceId];

        IBEP20 token = IBEP20(council.tokenContractAddress());

        // transfer token to space creator
        if (space.dealFeeRate > 0) {
            token.transfer(space.creator, info.price.mul(space.dealFeeRate).div(1000));
        }
    
        // transfer to info owner
        token.transfer(info.owner, info.price.mul(1000 - globalDealFeeRate - space.dealFeeRate).div(1000));

        deal.status = 2;

    }

    function cancelDeal(uint32 dealId) external {
        Deal storage deal = deals[dealId];
        require(deal.status == 1, "deal is not exist or status incorrect");

        if (_msgSender() != address(council)) {
            if (_msgSender() == council.userContractAddress()) {
                require(_txOrigin() == deal.maker, "you aren't the deal maker");
            } else {
                revert("Esaydeal: FORBIDDEN");
            }
        }

        Info memory info = infos[deal.infoId];

        // refund token
        IBEP20 token = IBEP20(council.tokenContractAddress());
        token.transfer(deal.maker, info.price);

        deal.status = 0;
    }

    /**
        Add space by council member
     */
    function addSpace(string memory name, string memory description, uint32 dealFeeRate) external viaCouncil {
        require(dealFeeRate <= 100, "fee rate too high");
        spaceCount++;
        spaces[spaceCount] = Space({
            name: name,
            description: description,
            creator: _txOrigin(),
            totalInfos: 0,
            totalDeals: 0,
            follows: 0,
            dealFeeRate: dealFeeRate,
            blockTimestamp: _blockTimestamp(),
            status: 1
        });
    }

    /**
        Hide space by creator
     */
    function hideSpace(uint32 spaceId) external viaCouncil {
        Space storage space = spaces[spaceId];
        require(_txOrigin() == space.creator, "you are not the space creator");

        space.status = 0;
    }

    function increaseSpaceFollows(uint32 spaceId) external {
        Space storage space = spaces[spaceId];
        require(space.status == 1, "space is not exist or status incorrect");
        space.follows++;
    }

    function decreaseSpaceFollows(uint32 spaceId) external {
        Space storage space = spaces[spaceId];
        require(space.status == 1, "space is not exist or status incorrect");
        space.follows--;
    }

    /**
        Update space deal fee rate by creator
     */
    function updateDealFeeRateForSpace(uint32 spaceId, uint32 rate) external viaCouncil {
        Space storage space = spaces[spaceId];

        require(rate <= 100, "fee rate too high");
        require(_txOrigin() == space.creator, "you are not the space creator");

        space.dealFeeRate = rate;
    }

    /**
        Update global deal fee rate by proposal
     */
    function updateGlobalDealFeeRate(uint32 rate) external viaCouncil {
        require(rate <= 100, "fee rate too high");
        globalDealFeeRate = rate;
    }

    // ============ Helpers ============

    function getInfoIdsBySpaceIds(
        uint32[] memory spaceIds, 
        uint32 page, 
        uint32 pageSize
    ) public view returns(uint32[] memory, uint32) {
        uint32[] memory ids = new uint32[](0);
        uint32 idx = 0;
        
        if (spaceIds.length == 0) {
            return (ids, 0);
        }

        for (uint32 i = 0; i < infoCount; i++) {
            Info memory info = infos[i];
            for (uint32 j = 0; j < spaceIds.length; j++) {
                if (info.spaceId == spaceIds[j]) {
                    ids[idx] = i;
                    idx++;
                }
            }
        }

        if (ids.length <= 0) {
            return (ids, 0);
        }

        if (pageSize > MAX_PAGE_SIZE) {
            pageSize = MAX_PAGE_SIZE;
        }

        uint32 totalPage = uint32(ids.length)/pageSize + 1;
        if (page < 1) {
            page = 1;
        } else if (page > totalPage) {
            page = page;
        }

        uint32[] memory tmpIds = new uint32[](0);
        uint32 tidx = 0;

        uint32 startIdx = (page-1) * pageSize;
        uint32 endIdx = page * pageSize;

        if (endIdx > ids.length) {
            endIdx = uint32(ids.length);
        }
        
        for (uint32 i = startIdx; i < endIdx; i++) {
            tmpIds[tidx] = ids[i];
            tidx++;
        }

        return (tmpIds, uint32(ids.length));
    }

}