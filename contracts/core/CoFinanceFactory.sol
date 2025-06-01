// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./CoFinancePool.sol";
import "./LiquidityToken.sol";

contract CoFinanceFactory {
    address public immutable owner;
    address[] public allPools;
    mapping(address => mapping(address => address)) public pools;

    event PoolCreated(address indexed pool, address indexed token0, address indexed token1, address liquidityToken);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    function createPool(
        address tokenA,
        address tokenB,
        string memory liquidityTokenName,
        string memory liquidityTokenSymbol,
        address priceOracle
    ) external onlyOwner returns (address pool) {
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
    }

    function getAllPools() external view returns (address[] memory) {
        return allPools;
    }
}