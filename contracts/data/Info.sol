// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

library Info {
    struct Data {
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

    function add(
        mapping(uint32 => Info.Data) storage self,
        uint32 id,
        uint32 spaceId, 
        uint8 iType,
        string memory title, 
        string memory content, 
        string memory memo,
        address owner,
        uint256 price,
        uint256 qty,
        address acceptToken
    ) internal {
        Info.Data storage info = self[id];
        info.id = id;
        info.spaceId = spaceId;
        info.iType = iType;
        info.title = title;
        info.content = content;
        info.memo = memo;
        info.owner = owner;
        info.price = price;
        info.qty = qty;
        info.acceptToken = acceptToken;
        info.timestamp = block.timestamp;
        info.status = 1;
    }

    function get(
        mapping(uint32 => Info.Data) storage self,
        uint32 id
    ) internal view returns (Info.Data storage info) {
        info = self[id];
    }

    function hide(
        mapping(uint32 => Info.Data) storage self,
        uint32 id
    ) internal {
        require(self[id].status == 1, "info status incorrect");
        self[id].status = 0;
    }

    function filter(
        mapping(uint32 => Info.Data) storage self,
        uint32[] memory spaceIds, 
        uint8[] memory status,
        address[] memory owners,
        uint32 page, 
        uint32 pageSize,
        bool desc,
        uint32 infoCount
    ) internal view returns(uint32[] memory, uint32) {
       
        uint32[] memory ids = new uint32[](infoCount);
        uint32 idx = 0;
        
        for (
            uint32 i = (desc ? infoCount : 0); 
            (desc ? i > 0 : i < infoCount); 
            (desc ? i-- : i++)
        ) {
            Info.Data memory info = self[desc ? i : i+1];

            if (spaceIds.length > 0) {
                for (uint32 j = 0; j < spaceIds.length; j++) {
                    if (info.spaceId == spaceIds[j]) {
                        ids[idx++] = desc ? i : i+1;
                    }
                }
            } else if (status.length > 0) {
                for (uint32 j = 0; j < status.length; j++) {
                    if (info.status == status[j]) {
                        ids[idx++] = desc ? i : i+1;
                    }
                }
            } else if (owners.length > 0) {
                for (uint32 j = 0; j < owners.length; j++) {
                    if (info.owner == owners[j]) {
                        ids[idx++] = desc ? i : i+1;
                    }
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
            tmpIds[tidx++] = ids[i];
        }

        return (tmpIds, idx);
    }

}