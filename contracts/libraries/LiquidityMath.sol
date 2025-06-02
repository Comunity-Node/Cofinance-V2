// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./TickMath.sol";

library LiquidityMath {
    using Math for uint256;

    function calculateLiquidity(
        uint256 amount0,
        uint256 amount1,
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper
    ) external view returns (uint256 liquidity) {
        require(tickLower < tickUpper, "Invalid tick range");

        // Get sqrt price ratios at ticks
        uint256 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower); // Returns 1 << 96
        uint256 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper); // Returns 1 << 96

        // Ensure sqrtRatioAX96 <= sqrtRatioBX96
        if (sqrtRatioAX96 > sqrtRatioBX96) {
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        }

        // Normalize to prevent overflow
        uint256 priceProduct = (sqrtRatioBX96 * sqrtRatioAX96) >> 96; // (1 << 96 * 1 << 96) >> 96 = 1 << 96
        uint256 denominator;

        if (sqrtPriceX96 <= sqrtRatioAX96) {
            // Current price below range: use amount0
            denominator = sqrtRatioBX96 - sqrtRatioAX96;
            if (denominator == 0) {
                liquidity = amount0; // Fallback to amount0 if ticks are equal
            } else {
                liquidity = (amount0 * priceProduct) / denominator;
            }
        } else if (sqrtPriceX96 < sqrtRatioBX96) {
            // Current price in range: use amount1
            denominator = sqrtRatioBX96 - sqrtPriceX96;
            liquidity = (amount1 * priceProduct) / denominator;
        } else {
            // Current price above range: use amount1
            denominator = sqrtPriceX96 - sqrtRatioAX96;
            if (denominator == 0) {
                liquidity = amount1; // Fallback to amount1 if ticks are equal
            } else {
                liquidity = (amount1 * priceProduct) / denominator;
            }
        }

        return liquidity;
    }
}