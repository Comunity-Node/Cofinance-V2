// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../oracle/PriceOracle.sol";
import "../lending/LendingPool.sol";

contract LiquidationLogic {
    using SafeERC20 for IERC20;
    using Math for uint256;

    LendingPool public immutable lendingPool;
    PriceOracle public immutable priceOracle;
    address public immutable owner;

    uint256 public constant LIQUIDATION_BONUS = 5; // 5% bonus for liquidators
    uint256 public constant MAX_LTV = 80; // 80% max LTV

    event Liquidated(
        address indexed borrower,
        address indexed liquidator,
        uint256 collateralAmount0,
        uint256 collateralAmount1,
        uint256 debtCovered
    );

    constructor(address _lendingPool, address _priceOracle) {
        lendingPool = LendingPool(_lendingPool);
        priceOracle = PriceOracle(_priceOracle);
        owner = msg.sender;
    }

    function isLiquidatable(address borrower) public view returns (bool) {
        uint256 borrowedAmount = lendingPool.borrowed(borrower);
        if (borrowedAmount == 0) return false;

        (uint256 collateral0, uint256 collateral1) = (
            lendingPool.collateral0(borrower),
            lendingPool.collateral1(borrower)
        );
        uint256 price = priceOracle.getPrice(address(lendingPool.token0()), address(lendingPool.token1()));
        uint256 collateralValue = collateral0 + (collateral1 * price) / 1e18;
        uint256 maxLoanValue = collateralValue * MAX_LTV / 100;

        return borrowedAmount > maxLoanValue;
    }

    function liquidate(address borrower, address liquidator) external {
        require(isLiquidatable(borrower), "Loan not liquidatable");
        require(liquidator != borrower, "Cannot liquidate own loan");

        uint256 borrowedAmount = lendingPool.borrowed(borrower);
        (uint256 collateral0, uint256 collateral1) = (
            lendingPool.collateral0(borrower),
            lendingPool.collateral1(borrower)
        );

        uint256 debtToCover = borrowedAmount;
        uint256 collateralValueInToken0 = collateral0 + (collateral1 * priceOracle.getPrice(address(lendingPool.token0()), address(lendingPool.token1()))) / 1e18;
        uint256 collateralToLiquidate = debtToCover * (100 + LIQUIDATION_BONUS) / MAX_LTV;

        require(collateralValueInToken0 >= collateralToLiquidate, "Insufficient collateral");

        if (collateral0 > 0) {
            lendingPool.token0().safeTransfer(liquidator, collateral0);
            lendingPool.updateCollateral0(borrower, 0);
        }
        if (collateral1 > 0) {
            lendingPool.token1().safeTransfer(liquidator, collateral1);
            lendingPool.updateCollateral1(borrower, 0);
        }
        lendingPool.updateBorrowed(borrower, 0);

        emit Liquidated(borrower, liquidator, collateral0, collateral1, debtToCover);
    }

    function seizeCollateral(address borrower) external {
        require(msg.sender == owner, "Only owner");
        require(isLiquidatable(borrower), "Loan not liquidatable");

        uint256 collateral0 = lendingPool.collateral0(borrower);
        uint256 collateral1 = lendingPool.collateral1(borrower);

        if (collateral0 > 0) {
            lendingPool.token0().safeTransfer(owner, collateral0);
            lendingPool.updateCollateral0(borrower, 0);
        }
        if (collateral1 > 0) {
            lendingPool.token1().safeTransfer(owner, collateral1);
            lendingPool.updateCollateral1(borrower, 0);
        }

        lendingPool.updateBorrowed(borrower, 0);

        emit Liquidated(borrower, owner, collateral0, collateral1, lendingPool.borrowed(borrower));
    }
}