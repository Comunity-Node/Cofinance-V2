// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract Presale {
    using SafeERC20 for IERC20;
    using Math for uint256;

    IERC20 public immutable saleToken;
    IERC20 public immutable paymentToken;
    address public immutable owner;
    uint256 public immutable startTime;
    uint256 public immutable endTime;
    uint256 public immutable tokenPrice;
    uint256 public immutable maxTokensForSale;
    uint256 public tokensSold;

    mapping(address => uint256) public contributions;

    event TokensPurchased(address indexed buyer, uint256 amount, uint256 cost);

    constructor(
        address _saleToken,
        address _paymentToken,
        uint256 _tokenPrice,
        uint256 _maxTokensForSale,
        uint256 _duration
    ) {
        saleToken = IERC20(_saleToken);
        paymentToken = IERC20(_paymentToken);
        owner = msg.sender;
        tokenPrice = _tokenPrice;
        maxTokensForSale = _maxTokensForSale;
        startTime = block.timestamp;
        endTime = block.timestamp + _duration;
    }

    function buyTokens(uint256 amount) external {
        require(block.timestamp >= startTime && block.timestamp <= endTime, "Presale not active");
        require(tokensSold + amount <= maxTokensForSale, "Exceeds max tokens");

        uint256 cost = amount / tokenPrice;
        paymentToken.safeTransferFrom(msg.sender, address(this), cost);
        saleToken.safeTransfer(msg.sender, amount);

        contributions[msg.sender] += amount;
        tokensSold += amount;

        emit TokensPurchased(msg.sender, amount, cost);
    }

    function withdrawFunds() external {
        require(msg.sender == owner, "Only owner");
        require(block.timestamp > endTime, "Presale not ended");
        paymentToken.safeTransfer(owner, paymentToken.balanceOf(address(this)));
    }
}