// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/TickMath.sol";
import "../libraries/LiquidityMath.sol";

library LiquidityManagerLib {
    struct LiquidityStorage {
        mapping(address => uint256) userLiquidity; 
        mapping(address => int24) tickLower; 
        mapping(address => int24) tickUpper; 
        uint256 totalLiquidity; 
    }

    function addLiquidity(
        LiquidityStorage storage self,
        address provider,
        uint256 amount0,
        uint256 amount1,
        int24 tickLower,
        int24 tickUpper,
        uint160 sqrtPriceX96
    ) internal returns (uint256 liquidityAmount) {
        require(amount0 > 0 && amount1 > 0, "Invalid amounts");
        require(tickLower < tickUpper, "Invalid ticks");
        require(tickLower >= TickMath.MIN_TICK && tickUpper <= TickMath.MAX_TICK, "Ticks out of range");

        liquidityAmount = LiquidityMath.calculateLiquidity(amount0, amount1, sqrtPriceX96, tickLower, tickUpper);

        self.userLiquidity[provider] += liquidityAmount;
        self.totalLiquidity += liquidityAmount;
        self.tickLower[provider] = tickLower;
        self.tickUpper[provider] = tickUpper;
    }

    function removeLiquidity(
        LiquidityStorage storage self,
        address provider,
        uint256 liquidityAmount
    ) internal returns (uint256 amount0, uint256 amount1) {
        require(self.userLiquidity[provider] >= liquidityAmount, "Insufficient liquidity");
        amount0 = (liquidityAmount * 1e18) / self.totalLiquidity; 
        amount1 = (liquidityAmount * 1e18) / self.totalLiquidity; 
        self.userLiquidity[provider] -= liquidityAmount;
        self.totalLiquidity -= liquidityAmount;
    }
}