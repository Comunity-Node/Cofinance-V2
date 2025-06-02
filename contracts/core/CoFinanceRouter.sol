// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./CoFinanceFactory.sol";
import "./CoFinancePool.sol";
import "../lending/LendingPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILendingPool {
    function borrow(address borrower, address token, uint256 amount, address collateralToken, uint256 collateralAmount) external;
    function repay(address borrower, uint256 amount) external;
    function addCollateral(address user, uint256 amount) external;
    function withdrawCollateral(address user, uint256 amount) external;
}

contract CoFinanceRouter {
    CoFinanceFactory public immutable factory;

    constructor(address _factory) {
        factory = CoFinanceFactory(_factory);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        int24 tickLower,
        int24 tickUpper
    ) external {
        address poolAddr = factory.getPool(tokenA, tokenB);
        require(poolAddr != address(0), "Pool does not exist");
        IERC20(tokenA).transferFrom(msg.sender, poolAddr, amountA);
        IERC20(tokenB).transferFrom(msg.sender, poolAddr, amountB);
        CoFinancePool(poolAddr).addLiquidity(amountA, amountB, tickLower, tickUpper);
    }

    // Swap tokens
    function swap(
        address tokenA,
        address tokenB,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut
    ) external {
        address poolAddr = factory.getPool(tokenA, tokenB);
        require(poolAddr != address(0), "Pool does not exist");
        require(tokenIn == tokenA || tokenIn == tokenB, "Invalid input token");
        IERC20(tokenIn).transferFrom(msg.sender, poolAddr, amountIn);
        uint256 amountOut = CoFinancePool(poolAddr).swap(tokenIn, amountIn, minAmountOut, msg.sender);
        require(amountOut >= minAmountOut, "Insufficient output amount");
    }


    // Borrow with collateral deposit
    function borrow(
        address tokenBorrow,
        uint256 amountBorrow,
        address tokenCollateral,
        uint256 amountCollateral
    ) external {
        address lendingPool = factory.getLendingPool(tokenBorrow, tokenCollateral);
        require(lendingPool != address(0), "Lending pool does not exist");
        IERC20(tokenCollateral).transferFrom(msg.sender, lendingPool, amountCollateral);
        ILendingPool(lendingPool).borrow(msg.sender, tokenBorrow, amountBorrow, tokenCollateral, amountCollateral);
    }

    // Repay borrowed amount
    function repay(
        address tokenBorrow,
        address tokenCollateral,
        uint256 amountRepay
    ) external {
        address lendingPool = factory.getLendingPool(tokenBorrow, tokenCollateral);
        require(lendingPool != address(0), "Lending pool does not exist");

        // Transfer repay tokens to lending pool
        IERC20(tokenBorrow).transferFrom(msg.sender, lendingPool, amountRepay);

        ILendingPool(lendingPool).repay(msg.sender, amountRepay);
    }

    // Add collateral separately
    function addCollateral(
        address tokenBorrow,
        address tokenCollateral,
        uint256 amountCollateral
    ) external {
        address lendingPool = factory.getLendingPool(tokenBorrow, tokenCollateral);
        require(lendingPool != address(0), "Lending pool does not exist");

        IERC20(tokenCollateral).transferFrom(msg.sender, lendingPool, amountCollateral);

        ILendingPool(lendingPool).addCollateral(msg.sender, amountCollateral);
    }

    // Withdraw collateral
    function withdrawCollateral(
        address tokenBorrow,
        address tokenCollateral,
        uint256 amountWithdraw
    ) external {
        address lendingPool = factory.getLendingPool(tokenBorrow, tokenCollateral);
        require(lendingPool != address(0), "Lending pool does not exist");

        ILendingPool(lendingPool).withdrawCollateral(msg.sender, amountWithdraw);
    }
}
