// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../libraries/TickMath.sol";
import "../libraries/LiquidityMath.sol";
import "../libraries/SwapMath.sol";
import "../oracle/CustomPriceOracle.sol";

interface ILiquidityToken is IERC20 {
    function mint(address to, uint256 amount) external;
}

contract CoFinancePool is AccessControl {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    IERC20 public immutable token0;
    IERC20 public immutable token1;
    ILiquidityToken public immutable liquidityToken;
    CustomPriceOracle public immutable priceOracle;

    mapping(address => uint256) public liquidity;

    event LiquidityAdded(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Swap(address indexed user, address indexed tokenIn, uint256 amountIn, uint256 amountOut);

    constructor(
        address _token0,
        address _token1,
        address _liquidityToken,
        address _priceOracle
    ) {
        require(_token0 != address(0) && _token1 != address(0), "Invalid token addresses");
        require(_liquidityToken != address(0), "Invalid liquidity token address");
        require(_priceOracle != address(0), "Invalid price oracle address");

        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        liquidityToken = ILiquidityToken(_liquidityToken);
        priceOracle = CustomPriceOracle(_priceOracle);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
    }

    function addLiquidity(
        uint256 amount0,
        uint256 amount1,
        int24 tickLower,
        int24 tickUpper
    ) external {
        require(amount0 > 0 && amount1 > 0, "Invalid amounts");
        require(tickLower < tickUpper, "Invalid ticks");
        require(tickLower >= TickMath.MIN_TICK && tickUpper <= TickMath.MAX_TICK, "Ticks out of range");

        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);
        (uint256 price0, uint256 price1) = priceOracle.getPricePair();
        uint160 sqrtPriceX96;
        if (address(token0) < address(token1)) {
            sqrtPriceX96 = encodeSqrtPriceX96FromPrices(price0, price1);
        } else {
            sqrtPriceX96 = encodeSqrtPriceX96FromPrices(price1, price0);
        }

        uint256 liquidityAmount = LiquidityMath.calculateLiquidity(
            amount0,
            amount1,
            sqrtPriceX96,
            tickLower,
            tickUpper
        );

        liquidityToken.mint(msg.sender, liquidityAmount);
        liquidity[msg.sender] += liquidityAmount;

        emit LiquidityAdded(msg.sender, amount0, amount1, liquidityAmount);
    }

    function swap(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient
    ) external returns (uint256 amountOut) {
        require(amountIn > 0, "Invalid amount");
        require(tokenIn == address(token0) || tokenIn == address(token1), "Invalid token");
        require(recipient != address(0), "Invalid recipient");
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        (uint256 price0, uint256 price1) = priceOracle.getPricePair();
        uint160 sqrtPriceInX96;
        uint160 sqrtPriceOutX96;
        if (tokenIn == address(token0)) {
            sqrtPriceInX96 = encodeSqrtPriceX96FromPrices(price0, price1);
            sqrtPriceOutX96 = encodeSqrtPriceX96FromPrices(price1, price0);
        } else {
            sqrtPriceInX96 = encodeSqrtPriceX96FromPrices(price1, price0);
            sqrtPriceOutX96 = encodeSqrtPriceX96FromPrices(price0, price1);
        }
        amountOut = SwapMath.calculateSwapOutput(
            amountIn,
            sqrtPriceInX96,
            sqrtPriceOutX96
        );

        require(amountOut >= amountOutMin, "Insufficient output amount");
        IERC20(tokenIn == address(token0) ? address(token1) : address(token0)).transfer(recipient, amountOut);
        emit Swap(msg.sender, tokenIn, amountIn, amountOut);
        return amountOut;
    }

    /// @dev Converts price ratio to sqrtPriceX96 used for Uniswap-style liquidity math
    function encodeSqrtPriceX96FromPrices(uint256 priceIn, uint256 priceOut) internal pure returns (uint160) {
        require(priceIn > 0 && priceOut > 0, "Invalid prices");
        uint256 ratioX192 = (priceOut << 192) / priceIn;
        uint256 sqrtRatioX96 = Math.sqrt(ratioX192);
        require(sqrtRatioX96 <= type(uint160).max, "sqrt ratio overflow");
        return uint160(sqrtRatioX96);
    }
}