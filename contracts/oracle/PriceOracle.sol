// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract PriceOracle {
    address public immutable poolAddress;
    uint256 public lastUpdateTime;
    uint160 public lastPrice; 
    uint256 public immutable updateInterval;

    constructor(address _poolAddress, uint256 _updateInterval) {
        poolAddress = _poolAddress;
        updateInterval = _updateInterval;
        lastPrice = 79228162514264337593543950336; 
        lastUpdateTime = block.timestamp;
    }

    function getPrice(address token0, address token1) external view returns (uint160) {
        return lastPrice;
    }

    function setPrice(uint160 sqrtPriceX96) external {
        require(block.timestamp >= lastUpdateTime + updateInterval, "Update interval not passed");
        lastPrice = sqrtPriceX96;
        lastUpdateTime = block.timestamp;
    }
}