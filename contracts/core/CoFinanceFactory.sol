// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./CoFinanceUnifiedPool.sol";
import "./LiquidityToken.sol";
import "./RewardManager.sol";
import "./LiquidityManager.sol";
import "../interface/ILiquidityToken.sol";

contract CoFinanceFactory {
    address public immutable owner;
    address[] public allPools;
    mapping(address => mapping(address => address)) public pools;

    event PoolCreated(address indexed pool, address indexed token0, address indexed token1, address liquidityToken, address rewardManager, address liquidityManager);

    constructor() {
        owner = msg.sender;
    }

    function createPool(
        address tokenA,
        address tokenB,
        string memory liquidityTokenName,
        string memory liquidityTokenSymbol,
        address priceFeed, // Single price feed or oracle
        address liquidationLogic
    ) external returns (address pool) {
        require(tokenA != tokenB && tokenA != address(0) && tokenB != address(0), "Invalid tokens");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(pools[token0][token1] == address(0), "Pool exists");

        LiquidityToken liquidityToken = new LiquidityToken(liquidityTokenName, liquidityTokenSymbol);
        RewardManager rewardManager = new RewardManager(token0, token1, address(liquidityToken), owner);
        LiquidityManager liquidityManager = new LiquidityManager(address(this));
        pool = address(new CoFinanceUnifiedPool(
            token0,
            token1,
            address(liquidityToken),
            priceFeed, // priceFeed0
            priceFeed, // priceFeed1 (use same for simplicity or adjust as needed)
            liquidationLogic,
            address(rewardManager),
            address(liquidityManager),
            address(this) // Pass factory as router for simplicity
        ));
        liquidityToken.setCoFinanceContract(pool);
        rewardManager.transferOwnership(pool);
        liquidityManager.transferOwnership(pool);
        pools[token0][token1] = pool;
        allPools.push(pool);

        emit PoolCreated(pool, token0, token1, address(liquidityToken), address(rewardManager), address(liquidityManager));
        return pool;
    }

    function getAllPools() external view returns (address[] memory) {
        return allPools;
    }

    function getPool(address tokenA, address tokenB) external view returns (address) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return pools[token0][token1];
    }
}