// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

import {SafeMath} from "./lib/SafeMath.sol";
import {SafeBEP20} from "./lib/SafeBEP20.sol";
import {IBEP20} from "./itf/IBEP20.sol";

contract ESDStorage {
    using SafeMath for uint256;

    // ============ Structs ============

    struct User {
        string nickName;
        string socialLink;
        string bio;
        uint256 lockedTokenAmount;
        bool isMerchant;
        bool isCouncilMember;
        address guarantor;
        uint32 score;
        uint256 timestamp;
        uint8 status; // 0 wait for guarantee, 1 normal, 2 banned
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

    struct Deal {
        uint32 id;
        uint32 infoId;
        uint256 qty;
        address maker;
        uint256 timestamp;
        uint8 status; // 0 canceled, 1 normal, 2 confirmed
    }

    struct Proposal {
        uint32 id;
        address proposer;
        string title;
        string description;
        bytes callData;
        uint256 tipsAmount;
        uint256 ayesAttachedTokenAmount;
        uint256 naysAttachedTokenAmount;
        uint256 timestamp;
        uint256 expireTimestamp;
        // 1 referenda 2 fail 3 council member second 4 passed
        uint8 status; 
    }

    // ============ States ============

    uint32 immutable MAX_PAGE_SIZE = 100;

    address public esdTokenAddress;

    address[] public registerQueue;
    uint32 public registerQueueSize = 1000;
    mapping(address => User) public users;
    mapping(address => uint32[]) public followedSpaceIds;

    uint32 public spaceCount;
    mapping(uint32 => Space) public spaces;

    uint32 public infoCount = 0;
    mapping(uint32 => Info) public infos;

    uint32 public dealCount = 0;
    mapping(uint32 => Deal) public deals;

    // council config
    uint32 public proposalCount = 0;
    uint256 public proposalTipsMinAmount = 100 * 10 ** 18;
    uint256 public proposalVotingDuration = 10 seconds;

    uint8 public votingAttachedTokenFactor = 10;
    mapping(uint32 => Proposal) public proposals;
    mapping(address => bool) public haveReferendum;

    address[] public councilMembers;
    mapping(uint32 => address[]) proposalAyes;
    mapping(uint32 => address[]) proposalNays;
    mapping(uint32 => address[]) public proposalSeconds;

    // ============ Helper functions ============

    function _removeAddressFromReqisterQueue(address _address) internal {
        address[] memory queue = registerQueue;

        bool changed = false;
        for (uint256 i = 0; i < queue.length; i++) {
            if (queue[i] == _address) {
                queue[i] = queue[queue.length - 1];
                changed = true;
                break;
            }
        }
        if (changed) {
            registerQueue = queue;
            registerQueue.pop();
        }
    }
    
    function getInfoIdsBySpaceIds(
        uint32[] memory spaceIds, 
        uint32 page, 
        uint32 pageSize,
        bool desc
    ) public view returns(uint32[] memory, uint32) {
        if (pageSize > MAX_PAGE_SIZE) {
            pageSize = MAX_PAGE_SIZE;
        }

        uint32[] memory ids = new uint32[](infoCount);
        uint32 idx = 0;
        
        for (
            uint32 i = (desc ? infoCount : 0); 
            (desc ? i > 0 : i < infoCount); 
            (desc ? i-- : i++)
        ) {
            Info memory info = infos[i+1];
            for (uint32 j = 0; j < spaceIds.length; j++) {
                if (info.spaceId == spaceIds[j]) {
                    ids[idx] = i+1;
                    idx++;
                }
            }
        }

        if (idx <= 0) {
            return (new uint32[](0), 0);
        }

        uint32 totalPage = (idx+(pageSize-1))/pageSize;
        if (page == 0) {
            page = 1;
        }
        uint32 resultSize = pageSize;
        if (page >= totalPage) {
            page = totalPage;
            resultSize = idx%pageSize > 0 ? idx%pageSize : pageSize;
        }
        
        uint32[] memory tmpIds = new uint32[](resultSize);

        uint32 tidx = 0;
        uint32 startIdx = (page-1) * pageSize;
        uint32 endIdx = page * pageSize;

        if (endIdx > idx) {
            endIdx = idx;
        }
        
        for (uint32 i = startIdx; i < endIdx; i++) {
            tmpIds[tidx] = ids[i];
            tidx++;
        }

        return (tmpIds, idx);
    }
}