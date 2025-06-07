// SPDX-License-Identifier: MIT


pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./CustomPriceFeed.sol";

contract CustomPriceOracle is Ownable {
    // Mapping of token addresses to CustomPriceFeed contracts
    mapping(address => address) public priceFeeds;

    event PriceFeedUpdated(address indexed token, address indexed priceFeed);

    constructor() Ownable(msg.sender) {}

    // Set or update the price feed for a token
    function setPriceFeed(address token, address priceFeed) external onlyOwner {
        require(token != address(0), "Invalid token address");
        require(priceFeed != address(0), "Invalid price feed address");
        priceFeeds[token] = priceFeed;
        emit PriceFeedUpdated(token, priceFeed);
    }

    // Get prices for a token pair (e.g., token0 and token1 in USD)
    function getPricePair(address token0, address token1) external view returns (uint256 price0, uint256 price1) {
        require(priceFeeds[token0] != address(0), "No price feed for token0");
        require(priceFeeds[token1] != address(0), "No price feed for token1");

        price0 = getPrice(token0);
        price1 = getPrice(token1);
    }

    // Get price for a single token (e.g., in USD, scaled to 1e18)
    function getPrice(address token) public view returns (uint256) {
        require(priceFeeds[token] != address(0), "No price feed for token");

        CustomPriceFeed priceFeed = CustomPriceFeed(priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price from feed");

        // Scale price to 1e18 (assuming feed provides 8 decimals)
        uint8 decimals = priceFeed.decimals();
        return uint256(price) * 10 ** (18 - decimals);
    }
}