// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../libraries/TickMath.sol";
import "../libraries/LiquidityMath.sol";
import "../libraries/SwapMath.sol";
import "./LiquidityToken.sol";
import "../oracle/PriceOracle.sol";

contract CoFinancePool {
    using SafeERC20 for IERC20;
    using Math for uint256;

    IERC20 public immutable token0;
    IERC20 public immutable token1;
    LiquidityToken public immutable liquidityToken;
    PriceOracle public immutable priceOracle;
    address public immutable owner;

    struct Position {
        uint128 liquidity;
        int24 tickLower;
        int24 tickUpper;
        uint256 feeGrowth0;
        uint256 feeGrowth1;
    }

    mapping(bytes32 => Position) public positions;
    uint256 public swapFeePercent = 30; // 0.3% default fee
    uint256 public totalLiquidity;
    uint160 public currentSqrtPriceX96;

    event Swap(address indexed sender, uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out);
    event LiquidityAdded(address indexed provider, uint256 amount0, uint256 amount1, uint128 liquidity);
    event FeesUpdated(uint256 newFeePercent);

    constructor(address _token0, address _token1, address _liquidityToken, address _priceOracle) {
        require(_token0 < _token1, "Invalid token order");
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        liquidityToken = LiquidityToken(_liquidityToken);
        priceOracle = PriceOracle(_priceOracle);
        owner = msg.sender;
        currentSqrtPriceX96 = 79228162514264337593543950336; 
    }

    function swap(address tokenIn, uint256 amountIn, uint256 minAmountOut, address recipient) external returns (uint256 amountOut) {
        require(amountIn > 0, "Amount must be > 0");
        bool isToken0 = tokenIn == address(token0);
        (IERC20 tokenInContract, IERC20 tokenOutContract) = isToken0 ? (token0, token1) : (token1, token0);
        amountOut = SwapMath.calculateSwapOutput(amountIn, currentSqrtPriceX96, swapFeePercent);
        require(amountOut >= minAmountOut, "Insufficient output amount");

        tokenInContract.safeTransferFrom(msg.sender, address(this), amountIn);
        tokenOutContract.safeTransfer(recipient, amountOut);

        uint256 feeAmount = SwapMath.calculateFee(amountIn, swapFeePercent);
        bytes32 positionKey = keccak256(abi.encodePacked(msg.sender, TickMath.MIN_TICK, TickMath.MAX_TICK));
        if (isToken0) {
            positions[positionKey].feeGrowth0 += feeAmount;
        } else {
            positions[positionKey].feeGrowth1 += feeAmount;
        }
        currentSqrtPriceX96 = priceOracle.getPrice(address(token0), address(token1));

        emit Swap(msg.sender, isToken0 ? amountIn : 0, isToken0 ? 0 : amountIn, isToken0 ? 0 : amountOut, isToken0 ? amountOut : 0);
    }

    function addLiquidity(uint256 amount0, uint256 amount1, int24 tickLower, int24 tickUpper) external returns (uint128 liquidity) {
        require(amount0 > 0 && amount1 > 0, "Invalid amounts");
        require(tickLower < tickUpper, "Invalid tick range");

        liquidity = LiquidityMath.calculateLiquidity(amount0, amount1, currentSqrtPriceX96, tickLower, tickUpper);

        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);
        liquidityToken.mint(msg.sender, liquidity);

        bytes32 positionKey = keccak256(abi.encodePacked(msg.sender, tickLower, tickUpper));
        positions[positionKey].liquidity += liquidity;
        positions[positionKey].tickLower = tickLower;
        positions[positionKey].tickUpper = tickUpper;
        totalLiquidity += liquidity;

        emit LiquidityAdded(msg.sender, amount0, amount1, liquidity);
    }

    function removeLiquidity(uint128 liquidity, int24 tickLower, int24 tickUpper) external {
        bytes32 positionKey = keccak256(abi.encodePacked(msg.sender, tickLower, tickUpper));
        Position memory position = positions[positionKey];
        require(position.liquidity >= liquidity, "Insufficient liquidity");

        uint256 amount0 = LiquidityMath.calculateAmount0(liquidity, tickLower, tickUpper, currentSqrtPriceX96);
        uint256 amount1 = LiquidityMath.calculateAmount1(liquidity, tickLower, tickUpper, currentSqrtPriceX96);

        positions[positionKey].liquidity -= liquidity;
        totalLiquidity -= liquidity;
        liquidityToken.burn(msg.sender, liquidity);

        token0.safeTransfer(msg.sender, amount0);
        token1.safeTransfer(msg.sender, amount1);
    }

    function setSwapFee(uint256 newFeePercent) external {
        require(msg.sender == owner, "Only owner");
        require(newFeePercent <= 1000, "Fee too high");
        swapFeePercent = newFeePercent;
        emit FeesUpdated(newFeePercent);
    }

    function updateSqrtPrice(uint160 newSqrtPriceX96) external {
        require(msg.sender == owner, "Only owner");
        currentSqrtPriceX96 = newSqrtPriceX96;
    }
}