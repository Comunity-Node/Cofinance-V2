// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import "./CoFinanceUnifiedPool.sol";
import "./CoFinanceFactory.sol";
import "./LiquidityToken.sol";
import "./RewardManager.sol";
import "./LiquidityManager.sol";
import "./LiquidationLogic.sol";
import "../libraries/TickMath.sol";
import "../libraries/LiquidityMath.sol";
import "../libraries/SwapMath.sol";
import "../interface/ILiquidityToken.sol"; // Import the interface

contract CoFinanceRouter is ReentrancyGuard, AccessControl {
    using Math for uint256;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    address public immutable owner;
    address[] public allPools;
    mapping(address => mapping(address => address)) public pools;

    // Chainlink CCIP Router
    IRouterClient public immutable ccipRouter; // Make immutable for gas optimization
    mapping(uint64 => address) public destinationContracts; // Chain selector to destination contract
    mapping(bytes32 => bool) public processedMessages;

    event PoolCreated(address indexed pool, address indexed token0, address indexed token1, address liquidityToken, address rewardManager, address liquidityManager);
    event TokensBridged(address indexed user, address token, uint256 amount, uint64 destinationChain, bytes32 messageId);
    event CrossChainSwapInitiated(address indexed user, address tokenIn, uint256 amountIn, uint64 destinationChain);
    event CrossChainLoanRequested(address indexed user, address collateralToken, uint256 collateralAmount, uint64 destinationChain);
    event LiquidityAdded(address indexed pool, address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Swap(address indexed pool, address indexed user, address indexed tokenIn, uint256 amountIn, uint256 amountOut, uint256 fee);
    event Borrow(address indexed pool, address indexed borrower, address token, uint256 amount, address collateralToken, uint256 collateralAmount);
    event Repaid(address indexed pool, address indexed borrower, uint256 amount, uint256 interest);
    event CollateralAdded(address indexed pool, address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed pool, address indexed user, uint256 amount);
    event Staked(address indexed pool, address indexed user, uint256 amount);
    event Withdrawn(address indexed pool, address indexed user, uint256 amount);
    event ParametersUpdated(address indexed pool, uint256 swapFee, uint256 interestRate, uint256 maxBorrowRatio);
    event TokenStatusUpdated(address indexed pool, address token, bool canLend, bool canCollateral);

    constructor(address _ccipRouter) {
        require(_ccipRouter != address(0), "Invalid CCIP router address");
        owner = msg.sender;
        ccipRouter = IRouterClient(_ccipRouter);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
    }

    // Factory Functions
    function createPool(
        address tokenA,
        address tokenB,
        string memory liquidityTokenName,
        string memory liquidityTokenSymbol,
        address priceFeedA,
        address priceFeedB,
        address liquidationLogic
    ) external onlyRole(MANAGER_ROLE) returns (address pool) {
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
            priceFeedA,
            priceFeedB,
            liquidationLogic,
            address(rewardManager),
            address(liquidityManager),
            address(this)
        ));
        liquidityToken.setCoFinanceContract(pool);
        rewardManager.transferOwnership(pool);
        liquidityManager.transferOwnership(pool);
        pools[token0][token1] = pool;
        allPools.push(pool);

        emit PoolCreated(pool, token0, token1, address(liquidityToken), address(rewardManager), address(liquidityManager));
        return pool;
    }

    // Pool Interaction Functions
    function swapExactInput(
        address pool,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountOut) {
        require(block.timestamp <= deadline, "Deadline exceeded");
        require(pools[tokenIn][tokenOut] == pool || pools[tokenOut][tokenIn] == pool, "Invalid pool");

        require(IERC20(tokenIn).transferFrom(msg.sender, pool, amountIn), "Token transfer failed");

        amountOut = CoFinanceUnifiedPool(pool).swap(
            msg.sender,
            tokenIn,
            amountIn,
            amountOutMin,
            recipient,
            deadline
        );

        emit Swap(pool, msg.sender, tokenIn, amountIn, amountOut, CoFinanceUnifiedPool(pool).swapFee());
        return amountOut;
    }

    function swapExactInputWithNative(
        address pool,
        address tokenOut,
        uint256 amountOutMin,
        address recipient,
        uint256 deadline
    ) external payable nonReentrant returns (uint256 amountOut) {
        require(block.timestamp <= deadline, "Deadline exceeded");
        require(msg.value > 0, "No ETH sent");

        address token0 = CoFinanceUnifiedPool(pool).getToken0();
        require(pools[token0][tokenOut] == pool, "Invalid pool");
        IWETH weth = IWETH(token0);
        require(token0 == address(weth), "Pool token0 must be WETH");

        weth.deposit{value: msg.value}();
        require(weth.transfer(pool, msg.value), "WETH transfer failed");

        amountOut = CoFinanceUnifiedPool(pool).swap(
            msg.sender,
            address(weth),
            msg.value,
            amountOutMin,
            recipient,
            deadline
        );

        emit Swap(pool, msg.sender, address(weth), msg.value, amountOut, CoFinanceUnifiedPool(pool).swapFee());
        return amountOut;
    }

    function addLiquiditySingleToken(
        address pool,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        int24 tickLower,
        int24 tickUpper,
        uint256 deadline
    ) external nonReentrant {
        require(block.timestamp <= deadline, "Deadline exceeded");
        require(pools[tokenIn][tokenOut] == pool || pools[tokenOut][tokenIn] == pool, "Invalid pool");

        require(IERC20(tokenIn).transferFrom(msg.sender, pool, amountIn), "Token transfer failed");

        (uint256 amount0, uint256 amount1) = _handleLiquiditySwap(pool, tokenIn, amountIn, deadline);

        CoFinanceUnifiedPool(pool).addLiquidity(
            msg.sender,
            amount0,
            amount1,
            tickLower,
            tickUpper
        );

        emit LiquidityAdded(pool, msg.sender, amount0, amount1, amount0 + amount1);
    }

    function _handleLiquiditySwap(
        address pool,
        address tokenIn,
        uint256 amountIn,
        uint256 deadline
    ) private returns (uint256 amount0, uint256 amount1) {
        address token0 = CoFinanceUnifiedPool(pool).getToken0();
        address token1 = CoFinanceUnifiedPool(pool).getToken1();

        (uint256 price0, uint256 price1) = CoFinanceUnifiedPool(pool).getPricePair(token0, token1);

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
    }

    function borrow(
        address pool,
        address token,
        uint256 amount,
        address collateralToken,
        uint256 collateralAmount
    ) external nonReentrant {
        require(pools[token][collateralToken] == pool || pools[collateralToken][token] == pool, "Invalid pool");
        require(IERC20(collateralToken).transferFrom(msg.sender, pool, collateralAmount), "Collateral transfer failed");
        CoFinanceUnifiedPool(pool).borrow(msg.sender, token, amount, collateralToken, collateralAmount);
        emit Borrow(pool, msg.sender, token, amount, collateralToken, collateralAmount);
    }

    function repay(address pool, uint256 amount) external nonReentrant {
        address borrowedToken = CoFinanceUnifiedPool(pool).borrowedToken(msg.sender);
        require(borrowedToken != address(0), "No borrow position");
        require(IERC20(borrowedToken).transferFrom(msg.sender, pool, amount), "Repay transfer failed");
        CoFinanceUnifiedPool(pool).repay(msg.sender, amount);
        emit Repaid(pool, msg.sender, amount, 0);
    }

    function addCollateral(address pool, uint256 amount) external nonReentrant {
        address collateralToken = CoFinanceUnifiedPool(pool).collateralToken(msg.sender);
        require(collateralToken != address(0), "No existing position");
        require(IERC20(collateralToken).transferFrom(msg.sender, pool, amount), "Collateral transfer failed");
        CoFinanceUnifiedPool(pool).addCollateral(msg.sender, amount);
        emit CollateralAdded(pool, msg.sender, amount);
    }

    function withdrawCollateral(address pool, uint256 amount) external nonReentrant {
        CoFinanceUnifiedPool(pool).withdrawCollateral(msg.sender, amount);
        emit CollateralWithdrawn(pool, msg.sender, amount);
    }

    function stake(address pool, uint256 amount) external nonReentrant {
        ILiquidityToken liquidityToken = ILiquidityToken(CoFinanceUnifiedPool(pool).liquidityToken());
        require(liquidityToken.balanceOf(msg.sender) >= amount, "Insufficient liquidity tokens");
        require(liquidityToken.transferFrom(msg.sender, pool, amount), "Stake transfer failed");
        CoFinanceUnifiedPool(pool).stake(msg.sender, amount);
        emit Staked(pool, msg.sender, amount);
    }

    function withdrawStake(address pool, uint256 amount) external nonReentrant {
        CoFinanceUnifiedPool(pool).withdrawStake(msg.sender, amount);
        emit Withdrawn(pool, msg.sender, amount);
    }

    function updateParameters(address pool, uint256 _swapFee, uint256 _interestRate, uint256 _maxBorrowRatio) external onlyRole(MANAGER_ROLE) {
        CoFinanceUnifiedPool(pool).updateParameters(_swapFee, _interestRate, _maxBorrowRatio);
        emit ParametersUpdated(pool, _swapFee, _interestRate, _maxBorrowRatio);
    }

    function updateTokenStatus(address pool, address token, bool canLend, bool canCollateral) external onlyRole(MANAGER_ROLE) {
        CoFinanceUnifiedPool(pool).updateTokenStatus(token, canLend, canCollateral);
        emit TokenStatusUpdated(pool, token, canLend, canCollateral);
    }

    // Cross-Chain Functions
    function setDestinationContract(uint64 chainSelector, address destination) external onlyRole(MANAGER_ROLE) {
        require(destination != address(0), "Invalid destination address");
        destinationContracts[chainSelector] = destination;
    }

    function swapExactInputCrossChain(
        address tokenIn,
        uint256 amountIn,
        uint64 destinationChainSelector,
        address recipient,
        uint256 deadline
    ) external payable nonReentrant {
        require(block.timestamp <= deadline, "Deadline exceeded");
        require(destinationContracts[destinationChainSelector] != address(0), "Invalid destination");
        require(IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn), "Token transfer failed");

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(destinationContracts[destinationChainSelector]),
            data: abi.encodeWithSelector(
                bytes4(keccak256("executeCrossChainSwap(address,address,uint256,address)")),
                msg.sender,
                tokenIn,
                amountIn,
                recipient
            ),
            tokenAmounts: new Client.EVMTokenAmount[](1),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 200_000})),
            feeToken: address(0)
        });

        message.tokenAmounts[0] = Client.EVMTokenAmount({token: tokenIn, amount: amountIn});
        bytes32 messageId = ccipRouter.ccipSend{value: msg.value}(destinationChainSelector, message);

        emit CrossChainSwapInitiated(msg.sender, tokenIn, amountIn, destinationChainSelector);
    }

    function requestCrossChainLoan(
        address collateralToken,
        uint256 collateralAmount,
        uint64 destinationChainSelector,
        address tokenToBorrow,
        uint256 borrowAmount
    ) external payable nonReentrant {
        require(destinationContracts[destinationChainSelector] != address(0), "Invalid destination");
        require(IERC20(collateralToken).transferFrom(msg.sender, address(this), collateralAmount), "Collateral transfer failed");

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(destinationContracts[destinationChainSelector]),
            data: abi.encodeWithSelector(
                bytes4(keccak256("executeCrossChainLoan(address,address,uint256,address,uint256)")),
                msg.sender,
                collateralToken,
                collateralAmount,
                tokenToBorrow,
                borrowAmount
            ),
            tokenAmounts: new Client.EVMTokenAmount[](1),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 200_000})),
            feeToken: address(0)
        });

        message.tokenAmounts[0] = Client.EVMTokenAmount({token: collateralToken, amount: collateralAmount});
        bytes32 messageId = ccipRouter.ccipSend{value: msg.value}(destinationChainSelector, message);

        emit CrossChainLoanRequested(msg.sender, collateralToken, collateralAmount, destinationChainSelector);
    }

    function receiveMessage(Client.Any2EVMMessage memory message) external nonReentrant {
        require(msg.sender == address(ccipRouter), "Only CCIP router");
        require(!processedMessages[message.messageId], "Message already processed");
        processedMessages[message.messageId] = true;

        (bool success,) = address(this).call(message.data);
        require(success, "Message execution failed");
    }

    function executeCrossChainSwap(address user, address tokenIn, uint256 amountIn, address recipient) external {
        require(msg.sender == address(this), "Only self via CCIP");
        address token0 = CoFinanceUnifiedPool(allPools[0]).getToken0();
        address token1 = CoFinanceUnifiedPool(allPools[0]).getToken1();
        address tokenOut = tokenIn == token0 ? token1 : token0;
        address pool = CoFinanceFactory.getPool(tokenIn, tokenOut);
        require(pool != address(0), "Pool does not exist");

        require(IERC20(tokenIn).transfer(pool, amountIn), "Token transfer failed");
        uint256 amountOut = CoFinanceUnifiedPool(pool).swap(
            user,
            tokenIn,
            amountIn,
            0,
            recipient,
            block.timestamp
        );

        emit Swap(pool, user, tokenIn, amountIn, amountOut, CoFinanceUnifiedPool(pool).swapFee());
    }

    function executeCrossChainLoan(
        address user,
        address collateralToken,
        uint256 collateralAmount,
        address tokenToBorrow,
        uint256 borrowAmount
    ) external {
        require(msg.sender == address(this), "Only self via CCIP");
        address pool = CoFinanceFactory.getPool(tokenToBorrow, collateralToken);
        require(pool != address(0), "Pool does not exist");

        require(IERC20(collateralToken).transfer(pool, collateralAmount), "Collateral transfer failed");
        CoFinanceUnifiedPool(pool).borrow(user, tokenToBorrow, borrowAmount, collateralToken, collateralAmount);

        emit Borrow(pool, user, tokenToBorrow, borrowAmount, collateralToken, collateralAmount);
    }
}

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
}