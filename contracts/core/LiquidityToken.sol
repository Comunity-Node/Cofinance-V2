// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LiquidityToken is ERC20 {
    using SafeERC20 for IERC20;

    address public immutable owner;
    address public cofinanceContract;

    modifier onlyCoFinance() {
        require(msg.sender == cofinanceContract, "Only CoFinance contract");
        _;
    }

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        owner = msg.sender;
    }

    function mint(address account, uint256 amount) external onlyCoFinance {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external onlyCoFinance {
        _burn(account, amount);
    }

    function setCoFinanceContract(address _cofinanceContract) external {
        require(msg.sender == owner, "Only owner");
        require(_cofinanceContract != address(0), "Invalid address");
        cofinanceContract = _cofinanceContract;
    }
}