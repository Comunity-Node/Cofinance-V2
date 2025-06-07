// SPDX-License-Identifier: MIT


pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../oracle/CustomPriceOracle.sol";
import "./CoFinanceUnifiedPool.sol";

contract LiquidationLogic is AccessControl {
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    CoFinanceUnifiedPool public immutable pool;
    CustomPriceOracle public immutable priceOracle;

    uint256 public constant LIQUIDATION_THRESHOLD = 120; // 120% collateralization ratio
    uint256 public constant LIQUIDATION_BONUS = 105; // 5% bonus for liquidator
    uint256 public constant PRECISION = 100;

    event Liquidation(
        address indexed user,
        address indexed liquidator,
        address indexed debtToken,
        uint256 debtAmount,
        address collateralToken,
        uint256 collateralAmount
    );

    constructor(address _pool, address _priceOracle) {
        pool = CoFinanceUnifiedPool(_pool);
        priceOracle = CustomPriceOracle(_priceOracle);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(LIQUIDATOR_ROLE, msg.sender);
    }

    function isLiquidatable(address user) external view returns (bool) {
        (uint256 borrowedValue, uint256 collateralValue) = getPositionValues(user);
        if (borrowedValue == 0 || collateralValue == 0) return false;
        return collateralValue * PRECISION < borrowedValue * LIQUIDATION_THRESHOLD;
    }

    function liquidate(address user, address liquidator) external onlyRole(LIQUIDATOR_ROLE) {
        require(user != address(0) && liquidator != address(0), "Invalid addresses");
        (uint256 borrowedValue, uint256 collateralValue) = getPositionValues(user);
        require(borrowedValue > 0 && collateralValue > 0, "No position to liquidate");
        require(collateralValue * PRECISION < borrowedValue * LIQUIDATION_THRESHOLD, "Position not liquidatable");

        address debtToken = pool.borrowedToken(user);
        address collateralToken = pool.collateralToken(user);
        uint256 debtAmount = pool.borrowed(user);
        uint256 collateralAmount = pool.collateral(user);
        uint256 debtValueInCollateral = (debtAmount * priceOracle.getPrice(debtToken)) / priceOracle.getPrice(collateralToken);
        uint256 collateralToLiquidator = (debtValueInCollateral * LIQUIDATION_BONUS) / PRECISION;

        require(collateralToLiquidator <= collateralAmount, "Insufficient collateral");
        IERC20(debtToken).transferFrom(liquidator, address(pool), debtAmount);
        IERC20(collateralToken).transferFrom(address(pool), liquidator, collateralToLiquidator);
        pool.liquidatePosition(user, debtAmount, collateralToLiquidator);
        emit Liquidation(user, liquidator, debtToken, debtAmount, collateralToken, collateralToLiquidator);
    }

    function getPositionValues(address user) public view returns (uint256 borrowedValue, uint256 collateralValue) {
        uint256 borrowedAmount = pool.borrowed(user);
        uint256 collateralAmount = pool.collateral(user);
        address borrowedToken = pool.borrowedToken(user);
        address collateralToken = pool.collateralToken(user);

        if (borrowedAmount > 0 && borrowedToken != address(0)) {
            borrowedValue = (borrowedAmount * priceOracle.getPrice(borrowedToken)) / 1e18;
        }
        if (collateralAmount > 0 && collateralToken != address(0)) {
            collateralValue = (collateralAmount * priceOracle.getPrice(collateralToken)) / 1e18;
        }
    }

    function updateLiquidatorRole(address account, bool grant) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (grant) _grantRole(LIQUIDATOR_ROLE, account);
        else _revokeRole(LIQUIDATOR_ROLE, account);
    }
}