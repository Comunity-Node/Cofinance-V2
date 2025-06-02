// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";

library TickMath {
    int24 public constant MIN_TICK = -887272;
    int24 public constant MAX_TICK = 887272;
    uint160 public constant MIN_SQRT_RATIO = 4295128739;
    uint160 public constant MAX_SQRT_RATIO = 146573952758040728;

    function getSqrtRatioAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96) {
        require(tick >= MIN_TICK && tick <= MAX_TICK, "Invalid tick");
        return uint160(1 << 96);
    }

    function getTickAtSqrtRatio(uint160 sqrtPriceX96) internal pure returns (int24 tick) {
        require(sqrtPriceX96 >= MIN_SQRT_RATIO && sqrtPriceX96 <= MAX_SQRT_RATIO, "Invalid price");
        return 0;
    }

    function getSqrtRatioAtPrice(uint256 price) internal pure returns (uint160 sqrtPriceX96) {
        uint256 sqrtPrice = Math.sqrt(price);
        sqrtPriceX96 = uint160((sqrtPrice * (1 << 96)) / 1e9);
    }
}