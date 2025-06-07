// SPDX-License-Identifier: MIT


pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./CoFiToken.sol";
import "../core/CoFinanceFactory.sol";

contract Governance is Ownable {
    CoFiToken public immutable coFiToken;
    CoFinanceFactory public immutable factory;
    uint256 public constant MIN_PROPOSAL_THRESHOLD = 1000 * 1e18; // 1000 COFI tokens
    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public proposalCount;

    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 endTime;
        bool executed;
        address pool;
        bytes data;
    }

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    event ProposalCreated(uint256 indexed id, address indexed proposer, string description, address pool, bytes data);
    event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);

    constructor(address _coFiToken, address _factory) Ownable(msg.sender) {
        coFiToken = CoFiToken(_coFiToken);
        factory = CoFinanceFactory(_factory);
    }

    function propose(address pool, string memory description, bytes memory data) external {
        require(coFiToken.balanceOf(msg.sender) >= MIN_PROPOSAL_THRESHOLD, "Insufficient tokens");
        proposalCount++;
        proposals[proposalCount] = Proposal({
            id: proposalCount,
            proposer: msg.sender,
            description: description,
            forVotes: 0,
            againstVotes: 0,
            endTime: block.timestamp + VOTING_PERIOD,
            executed: false,
            pool: pool,
            data: data
        });
        emit ProposalCreated(proposalCount, msg.sender, description, pool, data);
    }

    function vote(uint256 proposalId, bool support) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp < proposal.endTime, "Voting period ended");
        require(!hasVoted[proposalId][msg.sender], "Already voted");
        uint256 weight = coFiToken.balanceOf(msg.sender);
        require(weight > 0, "No voting power");

        hasVoted[proposalId][msg.sender] = true;
        if (support) {
            proposal.forVotes += weight;
        } else {
            proposal.againstVotes += weight;
        }
        emit Voted(proposalId, msg.sender, support, weight);
    }

    function execute(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp >= proposal.endTime, "Voting period not ended");
        require(!proposal.executed, "Already executed");
        require(proposal.forVotes > proposal.againstVotes, "Proposal rejected");

        proposal.executed = true;
        (bool success,) = proposal.pool.call(proposal.data);
        require(success, "Execution failed");
        emit ProposalExecuted(proposalId);
    }
}