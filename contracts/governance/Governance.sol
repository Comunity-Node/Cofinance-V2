// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./GovernanceToken.sol";

contract Governance {
    GovernanceToken public immutable govToken;
    uint256 public constant votingPeriod = 3 days;
    uint256 public proposalCount;

    struct Proposal {
        address proposer;
        string description;
        uint256 startTime;
        uint256 yesVotes;
        uint256 noVotes;
        bool executed;
    }

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    event ProposalCreated(uint256 indexed proposalId, address proposer, string description);
    event Voted(uint256 indexed proposalId, address voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);

    constructor(address _govToken) {
        govToken = GovernanceToken(_govToken);
    }

    function propose(string calldata description) external {
        require(govToken.balanceOf(msg.sender) > 0, "Must hold tokens");
        proposals[proposalCount] = Proposal({
            proposer: msg.sender,
            description: description,
            startTime: block.timestamp,
            yesVotes: 0,
            noVotes: 0,
            executed: false
        });
        emit ProposalCreated(proposalCount, msg.sender, description);
        proposalCount++;
    }

    function vote(uint256 proposalId, bool support) external {
        require(block.timestamp <= proposals[proposalId].startTime + votingPeriod, "Voting closed");
        require(!hasVoted[proposalId][msg.sender], "Already voted");

        uint256 weight = govToken.balanceOf(msg.sender);
        if (support) {
            proposals[proposalId].yesVotes += weight;
        } else {
            proposals[proposalId].noVotes += weight;
        }
        hasVoted[proposalId][msg.sender] = true;

        emit Voted(proposalId, msg.sender, support, weight);
    }

    function executeProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp > proposal.startTime + votingPeriod, "Voting not ended");
        require(!proposal.executed, "Already executed");
        require(proposal.yesVotes > proposal.noVotes, "Proposal rejected");

        proposal.executed = true;
        emit ProposalExecuted(proposalId);
    }
}