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

    // Mapping to track borrowed amounts (token0 or token1)
    mapping(address => uint256) public borrowed;
    // Mapping to track collateral amounts (token0 or token1)
    mapping(address => uint256) public collateral;
    // Mapping to track which token is borrowed
    mapping(address => address) public borrowedToken;
    // Mapping to track which token is used as collateral
    mapping(address => address) public collateralToken;

    event Borrow(address indexed borrower, address token, uint256 amount, address collateralToken, uint256 collateralAmount);
    event Liquidated(address indexed user, uint256 debtAmount, uint256 collateralAmount);

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
        address token,
        uint256 amount,
        address collateralTokenAddress,
        uint256 collateralAmount
    ) external {
        require(amount > 0 && collateralAmount > 0, "Invalid amounts");
        require(token == address(token0) || token == address(token1), "Invalid token");
        require(collateralTokenAddress == address(token0) || collateralTokenAddress == address(token1), "Invalid collateral");
        require(borrowed[msg.sender] == 0, "Existing borrow"); // One borrow per user for simplicity

        uint256 collateralValue = (collateralAmount * priceOracle.getPrice(collateralTokenAddress)) / 1e18;
        uint256 borrowValue = (amount * priceOracle.getPrice(token)) / 1e18;
        require(collateralValue >= borrowValue * 150 / 100, "Insufficient collateral"); // 150% collateralization

        IERC20(collateralTokenAddress).transferFrom(msg.sender, address(this), collateralAmount);
        IERC20(token).transfer(msg.sender, amount);

        borrowed[msg.sender] = amount;
        collateral[msg.sender] = collateralAmount;
        borrowedToken[msg.sender] = token;
        collateralToken[msg.sender] = collateralTokenAddress;

        emit Borrow(msg.sender, token, amount, collateralTokenAddress, collateralAmount);
    }

    function liquidatePosition(address user, uint256 debtAmount, uint256 collateralAmount) external {
        require(msg.sender == address(liquidationLogic), "Only LiquidationLogic");
        require(borrowed[user] >= debtAmount, "Invalid debt amount");
        require(collateral[user] >= collateralAmount, "Invalid collateral amount");

        borrowed[user] -= debtAmount;
        collateral[user] -= collateralAmount;

        // Clear token mappings if fully liquidated
        if (borrowed[user] == 0) {
            borrowedToken[user] = address(0);
            collateralToken[user] = address(0);
        }

        emit Liquidated(user, debtAmount, collateralAmount);
    }

    // Renamed getters to avoid conflict with state variables
    function getToken0() external view returns (address) {
        return address(token0);
    }

    function getToken1() external view returns (address) {
        return address(token1);
    }
}