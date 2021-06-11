// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0;

library Proposal {
    struct Data {
        address proposer;
        string title;
        string description;
        bytes callData;
        uint256 tipsAmount;
        address[] ayes;
        uint32 numAyes;
        address[] nays;
        uint32 numNays;
        address[] _seconds;
        uint32 numSeconds;
        uint256 ayesAttachedTokenAmount;
        uint256 naysAttachedTokenAmount;
        uint256 timestamp;
        // 1 referendum 2 defeated 3 second 4 executed
        uint8 status; 
    }

    function add(
        mapping(uint32 => Proposal.Data) storage self,
        uint32 id,
        address proposer,
        uint256 tipsAmount, 
        string memory title,
        string memory description,
        bytes memory callData
    ) internal {
        Proposal.Data storage proposal = self[id];
        proposal.proposer = proposer;
        proposal.title = title;
        proposal.description = description;
        proposal.callData = callData;
        proposal.tipsAmount = tipsAmount;
        proposal.ayesAttachedTokenAmount = 0;
        proposal.naysAttachedTokenAmount = 0;
        proposal.timestamp = block.timestamp;
        proposal.status = 1;
    }

    function get(
        mapping(uint32 => Proposal.Data) storage self,
        uint32 id
    ) internal view returns (Proposal.Data storage proposal) {
        proposal = self[id];
    }

    function vote(
        mapping(uint32 => Proposal.Data) storage self,
        uint32 id,
        bool aye,
        uint256 amount
    ) internal {
        Proposal.Data storage proposal = self[id];
        for (uint i = 0; i < proposal.ayes.length; i++) {
        if (proposal.ayes[i] == msg.sender) {
                revert("have voted aye");
            }
        }
        for (uint i = 0; i < proposal.nays.length; i++) {
            if (proposal.nays[i] == msg.sender) {
                revert("have voted nay");
            }
        }
        if (aye) {
            proposal.ayes.push(msg.sender);
            proposal.numAyes++;
            proposal.ayesAttachedTokenAmount += amount;
        } else {
            proposal.nays.push(msg.sender);
            proposal.numNays++;
            proposal.naysAttachedTokenAmount += amount;
        }
    }

    function second(
        mapping(uint32 => Proposal.Data) storage self,
        uint32 id
    ) internal returns (uint32) {
        Proposal.Data storage proposal = self[id];
        require(proposal.status == 3, "proposal status incorrect");
        for (uint i = 0; i < proposal._seconds.length; i++) {
            require(proposal._seconds[i] != msg.sender, "already second");
        }
        proposal._seconds.push(msg.sender);
        proposal.numSeconds++;
        return proposal.numSeconds;
    }

}