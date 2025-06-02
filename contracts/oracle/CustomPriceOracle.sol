// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract CustomPriceOracle is Ownable {
    address public token0;
    address public token1;
    uint256 public price0; // Price of token0 in token1 (18 decimals)
    uint256 public price1; // Price of token1 in token0 (18 decimals)
    uint256 public lastUpdate;

    event PriceUpdated(address indexed token, uint256 price, uint256 timestamp);

    constructor(address _token0, address _token1) Ownable(msg.sender) {
        token0 = _token0;
        token1 = _token1;
        price0 = 1e18; // Initial 1:1 price
        price1 = 1e18;
        lastUpdate = block.timestamp;
    }

    function setPrices(uint256 _price0, uint256 _price1) external onlyOwner {
        require(_price0 > 0 && _price1 > 0, "Invalid prices");
        price0 = _price0;
        price1 = _price1;
        lastUpdate = block.timestamp;
        emit PriceUpdated(token0, _price0, block.timestamp);
        emit PriceUpdated(token1, _price1, block.timestamp);
    }

    function getPrice(address token) external view returns (uint256) {
        require(token == token0 || token == token1, "Invalid token");
        return token == token0 ? price0 : price1;
    }

    function getPricePair() external view returns (uint256, uint256) {
        return (price0, price1);
    }
}