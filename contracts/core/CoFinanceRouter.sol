// SPDX-License-Identifier: MIT


pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./CoFinanceUnifiedPool.sol";
import "./CoFinanceFactory.sol";

contract Router is ReentrancyGuard {
    CoFinanceFactory public immutable factory;

    constructor(address _factory) {
        require(_factory != address(0), "Invalid factory address");
        factory = CoFinanceFactory(_factory);
    }

    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountOut) {
        require(block.timestamp <= deadline, "Deadline exceeded");
        address pool = factory.getPool(tokenIn, tokenOut);
        require(pool != address(0), "Pool does not exist");
        require(IERC20(tokenIn).transferFrom(msg.sender, pool, amountIn), "Token transfer failed");
        amountOut = CoFinanceUnifiedPool(pool).swap(msg.sender, tokenIn, amountIn, amountOutMin, recipient, deadline);
        return amountOut;
    }

    function addLiquiditySingleToken(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        int24 tickLower,
        int24 tickUpper,
        uint256 deadline
    ) external nonReentrant {
        require(block.timestamp <= deadline, "Deadline exceeded");
        address pool = factory.getPool(tokenIn, tokenOut);
        require(pool != address(0), "Pool does not exist");

        require(IERC20(tokenIn).transferFrom(msg.sender, pool, amountIn), "Token transfer failed");

        address token0 = CoFinanceUnifiedPool(pool).getToken0();
        address token1 = CoFinanceUnifiedPool(pool).getToken1();
        (uint256 price0, uint256 price1) = CoFinanceUnifiedPool(pool).priceOracle().getPricePair(token0, token1);
        uint256 amount0;
        uint256 amount1;

        if (tokenIn == token0) {
            amount0 = amountIn / 2;
            amount1 = (amount0 * price0) / price1;
            uint256 swapAmount = amountIn - amount0;
            if (swapAmount > 0) {
                CoFinanceUnifiedPool(pool).swap(msg.sender, tokenIn, swapAmount, 0, pool, deadline);
            }
        } else {
            amount1 = amountIn / 2;
            amount0 = (amount1 * price1) / price0;
            uint256 swapAmount = amountIn - amount1;
            if (swapAmount > 0) {
                CoFinanceUnifiedPool(pool).swap(msg.sender, tokenIn, swapAmount, 0, pool, deadline);
            }
        }

        // Remove the assignment to liquidityAmount since addLiquidity doesn't return anything
        CoFinanceUnifiedPool(pool).liquidityManager().addLiquidity(
            pool,
            msg.sender,
            amount0,
            amount1,
            tickLower,
            tickUpper
        );
    }

    function borrow(
        address pool,
        address token,
        uint256 amount,
        address collateralToken,
        uint256 collateralAmount
    ) external nonReentrant {
        require(factory.getPool(token, collateralToken) == pool, "Invalid pool");
        require(IERC20(collateralToken).transferFrom(msg.sender, pool, collateralAmount), "Collateral transfer failed");
        CoFinanceUnifiedPool(pool).borrow(msg.sender, token, amount, collateralToken, collateralAmount);
    }
}
