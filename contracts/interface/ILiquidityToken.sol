// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILiquidityToken is IERC20 {
    function mint(address to, uint256 amount) external;
    function setCoFinanceContract(address _coFinanceContract) external;
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}