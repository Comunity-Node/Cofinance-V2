// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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
    ) internal pure returns (uint128 liquidity) {
        require(amount0 > 0 || amount1 > 0, "Invalid amounts");
        require(tickLower < tickUpper, "Invalid tick range");
        require(tickLower >= TickMath.MIN_TICK && tickUpper <= TickMath.MAX_TICK, "Ticks out of bounds");

        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        uint160 sqrtPriceCurrentX96 = sqrtPriceX96;

        if (sqrtPriceCurrentX96 < sqrtPriceLowerX96) {
            sqrtPriceCurrentX96 = sqrtPriceLowerX96;
        } else if (sqrtPriceCurrentX96 > sqrtPriceUpperX96) {
            sqrtPriceCurrentX96 = sqrtPriceUpperX96;
        }
        if (sqrtPriceCurrentX96 <= sqrtPriceLowerX96) {
            liquidity = uint128(
                (amount0 * (sqrtPriceUpperX96 * sqrtPriceLowerX96) / 2**96) / (sqrtPriceUpperX96 - sqrtPriceLowerX96)
            );
        } else if (sqrtPriceCurrentX96 < sqrtPriceUpperX96) {
            uint128 liquidity0 = uint128(
                (amount0 * (sqrtPriceUpperX96 * sqrtPriceCurrentX96) / 2**96) / (sqrtPriceUpperX96 - sqrtPriceCurrentX96)
            );
            uint128 liquidity1 = uint128(
                (amount1 * 2**96) / (sqrtPriceCurrentX96 - sqrtPriceLowerX96)
            );
            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = uint128(
                (amount1 * 2**96) / (sqrtPriceUpperX96 - sqrtPriceLowerX96)
            );
        }

        require(liquidity > 0, "Zero liquidity");
        return liquidity;
    }

    function calculateAmount0(
        uint128 liquidity,
        int24 tickLower,
        int24 tickUpper,
        uint160 sqrtPriceX96
    ) internal pure returns (uint256 amount0) {
        require(liquidity > 0, "Zero liquidity");
        require(tickLower < tickUpper, "Invalid tick range");

        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        if (sqrtPriceX96 <= sqrtPriceLowerX96) {
            amount0 = (liquidity * (sqrtPriceUpperX96 - sqrtPriceLowerX96) * 2**96) / (sqrtPriceUpperX96 * sqrtPriceLowerX96);
        } else if (sqrtPriceX96 < sqrtPriceUpperX96) {
            amount0 = (liquidity * (sqrtPriceUpperX96 - sqrtPriceX96) * 2**96) / (sqrtPriceUpperX96 * sqrtPriceX96);
        } else {
            amount0 = 0;
        }

        return amount0;
    }

    function calculateAmount1(
        uint128 liquidity,
        int24 tickLower,
        int24 tickUpper,
        uint160 sqrtPriceX96
    ) internal pure returns (uint256 amount1) {
        require(liquidity > 0, "Zero liquidity");
        require(tickLower < tickUpper, "Invalid tick range");

        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        if (sqrtPriceX96 <= sqrtPriceLowerX96) {
            amount1 = 0;
        } else if (sqrtPriceX96 < sqrtPriceUpperX96) {
            amount1 = liquidity * (sqrtPriceX96 - sqrtPriceLowerX96) / 2**96;
        } else {
            amount1 = liquidity * (sqrtPriceUpperX96 - sqrtPriceLowerX96) / 2**96;
        }

        return amount1;
    }
}