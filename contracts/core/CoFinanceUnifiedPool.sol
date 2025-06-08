// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "./LiquidationLogic.sol";
import "./RewardManager.sol";
import "./LiquidityManager.sol";
import "../libraries/TickMath.sol";
import "../libraries/LiquidityMath.sol";
import "../libraries/SwapMath.sol";
import "../interface/ILiquidityToken.sol";

contract CoFinanceUnifiedPool is AccessControl, ReentrancyGuard {
    using Math for uint256;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    IERC20 public immutable token0;
    IERC20 public immutable token1;
    ILiquidityToken public immutable liquidityToken;
    AggregatorV3Interface public immutable priceFeed0;
    AggregatorV3Interface public immutable priceFeed1;
    LiquidationLogic public immutable liquidationLogic;
    RewardManager public immutable rewardManager;
    LiquidityManager public immutable liquidityManager;
    address public immutable router;

    mapping(address => uint256) public liquidity;
    mapping(address => uint256) public borrowed;
    mapping(address => uint256) public collateral;
    mapping(address => address) public borrowedToken;
    mapping(address => address) public collateralToken;
    uint256 public totalBorrowedToken0;
    uint256 public totalBorrowedToken1;
    uint256 public maxBorrowRatio = 80;
    mapping(address => uint256) public stakedBalance;
    uint256 public totalStaked;
    mapping(address => uint256) public lastUpdateTime;
    uint256 public swapFee = 300; // 0.3%
    uint256 public annualInterestRate = 500; // 5%
    mapping(address => uint256) public borrowStartTime;
    mapping(address => bool) public allowedLendingTokens;
    mapping(address => bool) public allowedCollateralTokens;

    event LiquidityAdded(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Swap(address indexed user, address indexed tokenIn, uint256 amountIn, uint256 amountOut, uint256 fee);
    event Borrow(address indexed borrower, address token, uint256 amount, address collateralToken, uint256 collateralAmount);
    event Repaid(address indexed borrower, uint256 amount, uint256 interest);
    event CollateralAdded(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event Liquidated(address indexed user, uint256 debtAmount, uint256 collateralAmount);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event ParametersUpdated(uint256 swapFee, uint256 interestRate, uint256 maxBorrowRatio);
    event TokenStatusUpdated(address token, bool canLend, bool canCollateral);

    constructor(
        address _token0,
        address _token1,
        address _liquidityToken,
        address _priceFeed0,
        address _priceFeed1,
        address _liquidationLogic,
        address _rewardManager,
        address _liquidityManager,
        address _router
    ) {
        require(_token0 != address(0) && _token1 != address(0), "Invalid token addresses");
        require(_liquidityToken != address(0), "Invalid liquidity token");
        require(_priceFeed0 != address(0) && _priceFeed1 != address(0), "Invalid price feeds");
        require(_liquidationLogic != address(0), "Invalid liquidation logic");
        require(_rewardManager != address(0), "Invalid reward manager");
        require(_liquidityManager != address(0), "Invalid liquidity manager");
        require(_router != address(0), "Invalid router");

        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        liquidityToken = ILiquidityToken(_liquidityToken);
        priceFeed0 = AggregatorV3Interface(_priceFeed0);
        priceFeed1 = AggregatorV3Interface(_priceFeed1);
        liquidationLogic = LiquidationLogic(_liquidationLogic);
        rewardManager = RewardManager(_rewardManager);
        liquidityManager = LiquidityManager(_liquidityManager);
        router = _router;
        allowedLendingTokens[_token0] = true;
        allowedLendingTokens[_token1] = true;
        allowedCollateralTokens[_token0] = true;
        allowedCollateralTokens[_token1] = true;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
    }

    function getPrice(address token) public view returns (uint256) {
        AggregatorV3Interface priceFeed = token == address(token0) ? priceFeed0 : priceFeed1;
        (, int256 price,, uint256 timeStamp,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        require(block.timestamp <= timeStamp + 3600, "Stale price data"); 
        return uint256(price) * 1e10; 
    }

    function getPricePair(address tokenA, address tokenB) public view returns (uint256 priceA, uint256 priceB) {
        priceA = getPrice(tokenA);
        priceB = getPrice(tokenB);
    }

    function getMaxBorrowable(address token) public view returns (uint256) {
        if (totalStaked == 0) return 0;
        (uint256 price0, uint256 price1) = getPricePair(address(token0), address(token1));
        uint256 totalValue = (token0.balanceOf(address(this)) * price0 + token1.balanceOf(address(this)) * price1) / 1e18;
        uint256 maxBorrowValue = (totalValue * maxBorrowRatio) / 100;
        uint256 tokenPrice = token == address(token0) ? price0 : price1;
        return (maxBorrowValue * 1e18) / tokenPrice;
    }

    function addLiquidity(
        address provider,
        uint256 amount0,
        uint256 amount1,
        int24 tickLower,
        int24 tickUpper
    ) external nonReentrant {
        require(msg.sender == address(liquidityManager) || msg.sender == router, "Only authorized");
        require(amount0 > 0 && amount1 > 0, "Invalid amounts");
        require(tickLower < tickUpper, "Invalid ticks");
        require(tickLower >= TickMath.MIN_TICK && tickUpper <= TickMath.MAX_TICK, "Ticks out of range");

        require(token0.transferFrom(provider, address(this), amount0), "Token0 transfer failed");
        require(token1.transferFrom(provider, address(this), amount1), "Token1 transfer failed");

        (uint256 price0, uint256 price1) = getPricePair(address(token0), address(token1));
        uint160 sqrtPriceX96 = address(token0) < address(token1)
            ? encodeSqrtPriceX96FromPrices(price0, price1)
            : encodeSqrtPriceX96FromPrices(price1, price0);

        uint256 liquidityAmount = LiquidityMath.calculateLiquidity(amount0, amount1, sqrtPriceX96, tickLower, tickUpper);

        liquidityToken.mint(provider, liquidityAmount);
        liquidity[provider] += liquidityAmount;

        emit LiquidityAdded(provider, amount0, amount1, liquidityAmount);
    }

    function swap(
        address user,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountOut) {
        require(msg.sender == router, "Only router");
        require(block.timestamp <= deadline, "Deadline exceeded");
        require(amountIn > 0, "Invalid amount");
        require(tokenIn == address(token0) || tokenIn == address(token1), "Invalid token");
        require(recipient != address(0), "Invalid recipient");

        amountOut = _calculateAmountOut(tokenIn, amountIn);
        require(amountOut >= amountOutMin, "Insufficient output amount");
        uint256 fee = (amountIn * swapFee) / 10000;
        uint256 amountInAfterFee = amountIn - fee;

        if (tokenIn == address(token0)) {
            rewardManager.allocateSwapFees(user, fee, 0);
        } else {
            rewardManager.allocateSwapFees(user, 0, fee);
        }

        address tokenOut = tokenIn == address(token0) ? address(token1) : address(token0);
        require(IERC20(tokenOut).transfer(recipient, amountOut), "Output token transfer failed");

        emit Swap(user, tokenIn, amountInAfterFee, amountOut, fee);
        return amountOut;
    }

    function _calculateAmountOut(address tokenIn, uint256 amountIn) private view returns (uint256) {
        (uint256 price0, uint256 price1) = getPricePair(address(token0), address(token1));
        uint160 sqrtPriceInX96 = tokenIn == address(token0)
            ? encodeSqrtPriceX96FromPrices(price0, price1)
            : encodeSqrtPriceX96FromPrices(price1, price0);
        uint160 sqrtPriceOutX96 = tokenIn == address(token0)
            ? encodeSqrtPriceX96FromPrices(price1, price0)
            : encodeSqrtPriceX96FromPrices(price0, price1);

        return SwapMath.calculateSwapOutput(amountIn, sqrtPriceInX96, sqrtPriceOutX96);
    }

    function borrow(
        address borrower,
        address token,
        uint256 amount,
        address collateralTokenAddress,
        uint256 collateralAmount
    ) external nonReentrant {
        require(msg.sender == router, "Only router");
        require(amount > 0 && collateralAmount > 0, "Invalid amounts");
        require(allowedLendingTokens[token], "Token not allowed for lending");
        require(allowedCollateralTokens[collateralTokenAddress], "Token not allowed for collateral");
        require(borrowed[borrower] == 0, "Existing borrow");

        uint256 collateralValue = (collateralAmount * getPrice(collateralTokenAddress)) / 1e18;
        uint256 borrowValue = (amount * getPrice(token)) / 1e18;
        require(collateralValue >= borrowValue * 150 / 100, "Insufficient collateral");

        uint256 currentTotalBorrowed = token == address(token0) ? totalBorrowedToken0 : totalBorrowedToken1;
        require(currentTotalBorrowed + amount <= getMaxBorrowable(token), "Exceeds max borrow limit");

        require(IERC20(token).transfer(borrower, amount), "Borrow token transfer failed");

        borrowed[borrower] = amount;
        collateral[borrower] = collateralAmount;
        borrowedToken[borrower] = token;
        collateralToken[borrower] = collateralTokenAddress;
        borrowStartTime[borrower] = block.timestamp;
        if (token == address(token0)) {
            totalBorrowedToken0 += amount;
        } else {
            totalBorrowedToken1 += amount;
        }

        emit Borrow(borrower, token, amount, collateralTokenAddress, collateralAmount);
    }

    function repay(address borrower, uint256 amount) external nonReentrant {
        require(msg.sender == router, "Only router");
        require(borrowed[borrower] >= amount, "Invalid repay amount");
        require(borrowedToken[borrower] != address(0), "No borrow position");

        uint256 timeElapsed = block.timestamp - borrowStartTime[borrower];
        uint256 interest = (amount * annualInterestRate * timeElapsed) / (10000 * 365 days);
        uint256 totalRepay = amount + interest;

        require(IERC20(borrowedToken[borrower]).transferFrom(borrower, address(this), totalRepay), "Repay transfer failed");

        borrowed[borrower] -= amount;
        if (borrowedToken[borrower] == address(token0)) {
            totalBorrowedToken0 -= amount;
            rewardManager.allocateInterest(borrower, interest, 0);
        } else {
            totalBorrowedToken1 -= amount;
            rewardManager.allocateInterest(borrower, 0, interest);
        }

        if (borrowed[borrower] == 0) {
            borrowedToken[borrower] = address(0);
            collateralToken[borrower] = address(0);
            borrowStartTime[borrower] = 0;
        }

        emit Repaid(borrower, amount, interest);
    }

    function addCollateral(address user, uint256 amount) external nonReentrant {
        require(msg.sender == router, "Only router");
        require(amount > 0, "Invalid amount");
        require(collateralToken[user] != address(0), "No existing position");
        collateral[user] += amount;
        emit CollateralAdded(user, amount);
    }

    function withdrawCollateral(address user, uint256 amount) external nonReentrant {
        require(msg.sender == router, "Only router");
        require(collateral[user] >= amount, "Insufficient collateral");
        uint256 collateralValue = ((collateral[user] - amount) * getPrice(collateralToken[user])) / 1e18;
        uint256 borrowValue = (borrowed[user] * getPrice(borrowedToken[user])) / 1e18;
        require(collateralValue >= borrowValue * 150 / 100 || borrowed[user] == 0, "Insufficient collateral");

        collateral[user] -= amount;
        require(IERC20(collateralToken[user]).transfer(user, amount), "Collateral withdrawal failed");
        if (collateral[user] == 0 && borrowed[user] == 0) {
            collateralToken[user] = address(0);
            borrowedToken[user] = address(0);
            borrowStartTime[user] = 0;
        }
        emit CollateralWithdrawn(user, amount);
    }

    function liquidatePosition(address user, uint256 debtAmount, uint256 collateralAmount) external nonReentrant {
        require(msg.sender == address(liquidationLogic), "Only LiquidationLogic");
        require(borrowed[user] >= debtAmount, "Invalid debt amount");
        require(collateral[user] >= collateralAmount, "Invalid collateral amount");

        borrowed[user] -= debtAmount;
        collateral[user] -= collateralAmount;
        if (borrowedToken[user] == address(token0)) {
            totalBorrowedToken0 -= debtAmount;
        } else {
            totalBorrowedToken1 -= debtAmount;
        }

        if (borrowed[user] == 0) {
            borrowedToken[user] = address(0);
            collateralToken[user] = address(0);
            borrowStartTime[user] = 0;
        }

        emit Liquidated(user, debtAmount, collateralAmount);
    }

    function stake(address user, uint256 amount) external nonReentrant {
        require(msg.sender == router, "Only router");
        require(amount > 0, "Invalid amount");
        require(liquidityToken.balanceOf(user) >= amount, "Insufficient liquidity tokens");

        updateRewards(user);

        stakedBalance[user] += amount;
        totalStaked += amount;
        lastUpdateTime[user] = block.timestamp;

        emit Staked(user, amount);
    }

    function withdrawStake(address user, uint256 amount) external nonReentrant {
        require(msg.sender == router, "Only router");
        require(amount > 0 && amount <= stakedBalance[user], "Invalid amount");
        updateRewards(user);

        stakedBalance[user] -= amount;
        totalStaked -= amount;
        require(liquidityToken.transfer(user, amount), "Withdraw transfer failed");
        if (stakedBalance[user] == 0) {
            lastUpdateTime[user] = 0;
        }

        emit Withdrawn(user, amount);
    }

    function updateRewards(address user) internal {
        lastUpdateTime[user] = block.timestamp;
    }

    function updateParameters(uint256 _swapFee, uint256 _interestRate, uint256 _maxBorrowRatio) external onlyRole(MANAGER_ROLE) {
        require(_swapFee <= 1000, "Swap fee too high");
        require(_interestRate <= 2000, "Interest rate too high");
        require(_maxBorrowRatio <= 100, "Borrow ratio too high");
        swapFee = _swapFee;
        annualInterestRate = _interestRate;
        maxBorrowRatio = _maxBorrowRatio;
        emit ParametersUpdated(_swapFee, _interestRate, _maxBorrowRatio);
    }

    function updateTokenStatus(address token, bool canLend, bool canCollateral) external onlyRole(MANAGER_ROLE) {
        allowedLendingTokens[token] = canLend;
        allowedCollateralTokens[token] = canCollateral;
        emit TokenStatusUpdated(token, canLend, canCollateral);
    }

    function encodeSqrtPriceX96FromPrices(uint256 priceIn, uint256 priceOut) internal pure returns (uint160) {
        require(priceIn > 0 && priceOut > 0, "Invalid prices");
        uint256 ratioX96 = (priceOut * (1 << 96)) / priceIn;
        uint256 sqrtRatioX96 = sqrt(ratioX96);
        require(sqrtRatioX96 <= type(uint160).max, "Sqrt ratio overflow");
        return uint160(sqrtRatioX96);
    }

    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) >> 1;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) >> 1;
        }
        return y;
    }

    function getToken0() external view returns (address) {
        return address(token0);
    }

    function getToken1() external view returns (address) {
        return address(token1);
    }
}