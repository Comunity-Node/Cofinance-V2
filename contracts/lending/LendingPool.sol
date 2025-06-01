// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../oracle/PriceOracle.sol";
import "./LiquidationLogic.sol";

contract LendingPool {
    using SafeERC20 for IERC20;
    using Math for uint256;

    IERC20 public immutable token0;
    IERC20 public immutable token1;
    PriceOracle public immutable priceOracle;
    LiquidationLogic public immutable liquidationLogic;
    uint256 public constant MAX_LTV = 80; //  loan-to-value
    uint256 public constant INTEREST_RATE = 5; // monthly interest

    mapping(address => uint256) public collateral0;
    mapping(address => uint256) public collateral1;
    mapping(address => uint256) public borrowed;
    mapping(address => uint256) public loanStartTime;

    event Borrowed(address indexed borrower, address token, uint256 amount, uint256 collateral);
    event Repaid(address indexed borrower, uint256 amount);

    constructor(address _token0, address _token1, address _priceOracle, address _liquidationLogic) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        priceOracle = PriceOracle(_priceOracle);
        liquidationLogic = LiquidationLogic(_liquidationLogic);
    }

    function borrow(address token, uint256 amount, address collateralToken, uint256 collateralAmount) external {
        require(amount > 0 && collateralAmount > 0, "Invalid amounts");
        require(token == address(token0) || token == address(token1), "Invalid token");
        require(collateralToken == address(token0) || collateralToken == address(token1), "Invalid collateral");

        uint256 price = priceOracle.getPrice(address(token0), address(token1));
        uint256 collateralValue = collateralToken == address(token0) ? collateralAmount * price / 1e18 : collateralAmount * 1e18 / price;
        require(collateralValue >= amount * 100 / MAX_LTV, "Insufficient collateral");

        IERC20(token).safeTransfer(msg.sender, amount);
        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), collateralAmount);

        if (token == address(token0)) {
            borrowed[msg.sender] += amount;
            collateral1[msg.sender] += collateralAmount;
        } else {
            borrowed[msg.sender] += amount;
            collateral0[msg.sender] += collateralAmount;
        }
        loanStartTime[msg.sender] = block.timestamp;

        emit Borrowed(msg.sender, token, amount, collateralAmount);
    }

    function repay(address token, uint256 amount) external {
        require(borrowed[msg.sender] >= amount, "Invalid amount");
        require(token == address(token0) || token == address(token1), "Invalid token");

        uint256 interest = amount * INTEREST_RATE * (block.timestamp - loanStartTime[msg.sender]) / (30 days) / 100;
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount + interest);
        borrowed[msg.sender] -= amount;

        uint256 collateralToReturn = amount * 100 / MAX_LTV;
        if (token == address(token0)) {
            collateral1[msg.sender] -= collateralToReturn;
            token1.safeTransfer(msg.sender, collateralToReturn);
        } else {
            collateral0[msg.sender] -= collateralToReturn;
            token0.safeTransfer(msg.sender, collateralToReturn);
        }

        emit Repaid(msg.sender, amount);
    }

    function updateCollateral0(address borrower, uint256 amount) external {
        require(msg.sender == address(liquidationLogic), "Only liquidation logic");
        collateral0[borrower] = amount;
    }

    function updateCollateral1(address borrower, uint256 amount) external {
        require(msg.sender == address(liquidationLogic), "Only liquidation logic");
        collateral1[borrower] = amount;
    }

    function updateBorrowed(address borrower, uint256 amount) external {
        require(msg.sender == address(liquidationLogic), "Only liquidation logic");
        borrowed[borrower] = amount;
    }
}