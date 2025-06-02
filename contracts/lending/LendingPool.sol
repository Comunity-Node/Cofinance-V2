// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./LiquidationLogic.sol";
import "../oracle/CustomPriceOracle.sol";

contract LendingPool is AccessControl {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    IERC20 public immutable token0;
    IERC20 public immutable token1;
    CustomPriceOracle public immutable priceOracle;
    LiquidationLogic public immutable liquidationLogic;

    mapping(address => uint256) public borrowed;
    mapping(address => uint256) public collateral;
    mapping(address => address) public borrowedToken;
    mapping(address => address) public collateralToken;

    event Borrow(address indexed borrower, address token, uint256 amount, address collateralToken, uint256 collateralAmount);
    event Liquidated(address indexed user, uint256 debtAmount, uint256 collateralAmount);
    event Repaid(address indexed borrower, uint256 amount);
    event CollateralAdded(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);

    constructor(
        address _token0,
        address _token1,
        address _priceOracle,
        address _liquidationLogic
    ) {
        require(_token0 != address(0) && _token1 != address(0), "Invalid token addresses");
        require(_priceOracle != address(0), "Invalid price oracle address");
        require(_liquidationLogic != address(0), "Invalid liquidation logic address");

        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        priceOracle = CustomPriceOracle(_priceOracle);
        liquidationLogic = LiquidationLogic(_liquidationLogic);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
    }

    function borrow(
        address borrower,
        address token,
        uint256 amount,
        address collateralTokenAddress,
        uint256 collateralAmount
    ) external {
        require(amount > 0 && collateralAmount > 0, "Invalid amounts");
        require(token == address(token0) || token == address(token1), "Invalid token");
        require(collateralTokenAddress == address(token0) || collateralTokenAddress == address(token1), "Invalid collateral");
        require(borrowed[borrower] == 0, "Existing borrow");

        uint256 collateralValue = (collateralAmount * priceOracle.getPrice(collateralTokenAddress)) / 1e18;
        uint256 borrowValue = (amount * priceOracle.getPrice(token)) / 1e18;
        require(collateralValue >= borrowValue * 150 / 100, "Insufficient collateral"); 
        IERC20(collateralTokenAddress).transferFrom(msg.sender, address(this), collateralAmount);
        IERC20(token).transfer(borrower, amount);

        borrowed[borrower] = amount;
        collateral[borrower] = collateralAmount;
        borrowedToken[borrower] = token;
        collateralToken[borrower] = collateralTokenAddress;

        emit Borrow(borrower, token, amount, collateralTokenAddress, collateralAmount);
    }

    function repay(address borrower, uint256 amount) external {
        require(borrowed[borrower] >= amount, "Invalid repay amount");
        require(borrowedToken[borrower] != address(0), "No borrow position");
        IERC20(borrowedToken[borrower]).transferFrom(msg.sender, address(this), amount);
        borrowed[borrower] -= amount;
        if (borrowed[borrower] == 0) {
            borrowedToken[borrower] = address(0);
            collateralToken[borrower] = address(0);
        }
        emit Repaid(borrower, amount);
    }

    function addCollateral(address user, uint256 amount) external {
        require(amount > 0, "Invalid amount");
        require(collateralToken[user] != address(0), "No existing position");
        IERC20(collateralToken[user]).transferFrom(msg.sender, address(this), amount);
        collateral[user] += amount;
        emit CollateralAdded(user, amount);
    }

    function withdrawCollateral(address user, uint256 amount) external {
        require(collateral[user] >= amount, "Insufficient collateral");
        uint256 collateralValue = ((collateral[user] - amount) * priceOracle.getPrice(collateralToken[user])) / 1e18;
        uint256 borrowValue = (borrowed[user] * priceOracle.getPrice(borrowedToken[user])) / 1e18;
        require(collateralValue >= borrowValue * 150 / 100 || borrowed[user] == 0, "Insufficient collateral after withdrawal");
        collateral[user] -= amount;
        IERC20(collateralToken[user]).transfer(user, amount);
        if (collateral[user] == 0 && borrowed[user] == 0) {
            collateralToken[user] = address(0);
            borrowedToken[user] = address(0);
        }
        emit CollateralWithdrawn(user, amount);
    }

    function liquidatePosition(address user, uint256 debtAmount, uint256 collateralAmount) external {
        require(msg.sender == address(liquidationLogic), "Only LiquidationLogic");
        require(borrowed[user] >= debtAmount, "Invalid debt amount");
        require(collateral[user] >= collateralAmount, "Invalid collateral amount");

        borrowed[user] -= debtAmount;
        collateral[user] -= collateralAmount;
        if (borrowed[user] == 0) {
            borrowedToken[user] = address(0);
            collateralToken[user] = address(0);
        }

        emit Liquidated(user, debtAmount, collateralAmount);
    }

    function getToken0() external view returns (address) {
        return address(token0);
    }

    function getToken1() external view returns (address) {
        return address(token1);
    }
}