// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./CoFinanceUnifiedPool.sol";
import "./CoFinanceFactory.sol";

contract LiquidityManager is Ownable {
    CoFinanceFactory public immutable factory;

    constructor(address _factory) Ownable(_factory) {
        require(_factory != address(0), "Invalid factory address");
        factory = CoFinanceFactory(_factory);
    }

    function addLiquidity(
        address pool,
        address provider,
        uint256 amount0,
        uint256 amount1,
        int24 tickLower,
        int24 tickUpper
    ) external onlyOwner {
        CoFinanceUnifiedPool(pool).addLiquidity(provider, amount0, amount1, tickLower, tickUpper);
    }
}