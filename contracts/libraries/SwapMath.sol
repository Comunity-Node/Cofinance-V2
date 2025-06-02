// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library SwapMath {
    /// @dev Calculates the output amount for a swap given input amount and sqrt price ratios
    /// @param amountIn The amount of input tokens
    /// @param sqrtPriceInX96 The sqrt price of the input token in terms of the output token (Q64.96)
    /// @param sqrtPriceOutX96 The sqrt price of the output token in terms of the input token (Q64.96)
    /// @return amountOut The amount of output tokens
    function calculateSwapOutput(
        uint256 amountIn,
        uint160 sqrtPriceInX96,
        uint160 sqrtPriceOutX96
    ) external pure returns (uint256 amountOut) {
        require(amountIn > 0, "Invalid input amount");
        require(sqrtPriceInX96 > 0 && sqrtPriceOutX96 > 0, "Invalid prices");

        // Calculate the price ratio: (sqrtPriceOutX96 / sqrtPriceInX96)^2
        // Since sqrtPriceX96 is Q64.96, we adjust for fixed-point arithmetic
        uint256 priceRatioX192 = (uint256(sqrtPriceOutX96) * (1 << 192)) / sqrtPriceInX96;
        uint256 price = priceRatioX192 >> 96; // Convert to Q96 for amount calculation

        // Calculate output: amountOut = amountIn * (priceOut / priceIn)
        amountOut = (amountIn * price) >> 96;

        require(amountOut > 0, "Zero output amount");
        return amountOut;
    }
}