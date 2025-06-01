// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";

library SwapMath {
    using Math for uint256;

    function calculateSwapOutput(uint256 amountIn, uint160 sqrtPriceX96, uint256 swapFeePercent) internal pure returns (uint256 amountOut) {
        uint256 fee = amountIn * swapFeePercent / 10000; // Fee in basis points
        uint256 amountInAfterFee = amountIn - fee;
        amountOut = amountInAfterFee * (uint256(sqrtPriceX96)) / 2**96; 
        return amountOut;
    }

    function calculateFee(uint256 amountIn, uint256 swapFeePercent) internal pure returns (uint256) {
        return amountIn* swapFeePercent / 10000; // Fee in basis points
    }
}