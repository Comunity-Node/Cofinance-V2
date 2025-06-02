// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./CoFinancePool.sol";
import "./LiquidityToken.sol";
import "../lending/LendingPool.sol";

contract CoFinanceFactory {
    address public immutable owner;
    address[] public allPools;
    address[] public allLendingPools;
    mapping(address => mapping(address => address)) public pools;
    mapping(address => mapping(address => address)) public lendingPools;

    event PoolCreated(address indexed pool, address indexed token0, address indexed token1, address liquidityToken);
    event LendingPoolCreated(address indexed lendingPool, address indexed tokenBorrow, address indexed tokenCollateral);

    constructor() {
        owner = msg.sender;
    }
    function createPool(
        address tokenA,
        address tokenB,
        string memory liquidityTokenName,
        string memory liquidityTokenSymbol,
        address priceOracle
    ) external returns (address pool) {
        require(tokenA != tokenB, "Identical tokens");
        require(tokenA != address(0) && tokenB != address(0), "Zero address");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(pools[token0][token1] == address(0), "Pool exists");

        LiquidityToken liquidityToken = new LiquidityToken(liquidityTokenName, liquidityTokenSymbol);
        pool = address(new CoFinancePool(token0, token1, address(liquidityToken), priceOracle));
        liquidityToken.setCoFinanceContract(pool);
        pools[token0][token1] = pool;
        allPools.push(pool);

        emit PoolCreated(pool, token0, token1, address(liquidityToken));
        return pool;
    }

    function createLendingPool(
        address tokenA,
        address tokenB,
        address priceOracle,
        address liquidationLogic
    ) external returns (address pool) {
        require(tokenA != tokenB, "Identical tokens");
        require(tokenA != address(0) && tokenB != address(0), "Zero address");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(lendingPools[token0][token1] == address(0), "Lending pool exists");
        pool = address(new LendingPool(token0, token1, priceOracle, liquidationLogic));
        lendingPools[token0][token1] = pool;
        allLendingPools.push(pool);
        emit LendingPoolCreated(pool, token0, token1);
        return pool;
    }

    function getAllPools() external view returns (address[] memory) {
        return allPools;
    }

    function getPool(address tokenA, address tokenB) external view returns (address) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return pools[token0][token1];
    }

    function getLendingPool(address tokenBorrow, address tokenCollateral) external view returns (address) {
        (address borrowToken, address collateralToken) = tokenBorrow < tokenCollateral
            ? (tokenBorrow, tokenCollateral)
            : (tokenCollateral, tokenBorrow);
        return lendingPools[borrowToken][collateralToken];
    }

    function getAllLendingPools() external view returns (address[] memory) {
        return allLendingPools;
    }
}