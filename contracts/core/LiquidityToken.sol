// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LiquidityToken is ERC20, Ownable {
    address public coFinanceContract;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) Ownable(msg.sender) {}

    modifier onlyCoFinance() {
        require(msg.sender == coFinanceContract, "Only CoFinance contract");
        _;
    }

    function setCoFinanceContract(address _coFinanceContract) external onlyOwner {
        require(_coFinanceContract != address(0), "Invalid address");
        coFinanceContract = _coFinanceContract;
    }

    function mint(address to, uint256 amount) external onlyCoFinance {
        _mint(to, amount);
    }
}