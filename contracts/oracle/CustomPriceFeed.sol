// SPDX-License-Identifier: MIT


pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract CustomPriceFeed is Ownable {
    uint8 public constant decimals = 8; // USD prices with 8 decimals
    uint80 public latestRoundId;
    int256 public latestPrice;
    uint256 public latestTimestamp;

    mapping(uint80 => int256) public priceHistory;
    mapping(uint80 => uint256) public timestampHistory;
    mapping(address => bool) public oracles;

    event PriceUpdated(uint80 indexed roundId, int256 price, uint256 timestamp);
    event OracleUpdated(address indexed oracle, bool authorized);

    constructor() Ownable(msg.sender) {
        oracles[msg.sender] = true;
    }

    // Update price (called by authorized oracles)
    function updatePrice(int256 price) external {
        require(oracles[msg.sender], "Unauthorized oracle");
        require(price > 0, "Invalid price");

        latestRoundId++;
        latestPrice = price;
        latestTimestamp = block.timestamp;

        priceHistory[latestRoundId] = price;
        timestampHistory[latestRoundId] = latestTimestamp;

        emit PriceUpdated(latestRoundId, price, latestTimestamp);
    }

    // Add or remove oracle
    function setOracle(address oracle, bool authorized) external onlyOwner {
        require(oracle != address(0), "Invalid oracle address");
        oracles[oracle] = authorized;
        emit OracleUpdated(oracle, authorized);
    }

    // Mimic Chainlink's latestRoundData
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 price,
        uint256 startedAt,
        uint256 timestamp,
        uint80 answeredInRound
    ) {
        return (
            latestRoundId,
            latestPrice,
            0, // startedAt not tracked
            latestTimestamp,
            latestRoundId
        );
    }

    // Get historical data
    function getRoundData(uint80 roundId) external view returns (
        uint80,
        int256,
        uint256,
        uint256,
        uint80
    ) {
        require(roundId <= latestRoundId, "Invalid round ID");
        return (
            roundId,
            priceHistory[roundId],
            0,
            timestampHistory[roundId],
            roundId
        );
    }
}