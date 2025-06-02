// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract Launchpad is Ownable {
    using Math for uint256;

    IERC20 public immutable saleToken;
    IERC20 public immutable paymentToken;
    uint256 public immutable tokenPrice; // Payment tokens per sale token (scaled by 1e18)
    uint256 public immutable totalTokensForSale;
    uint256 public immutable minPurchase;
    uint256 public immutable maxPurchase;
    uint256 public immutable startTime;
    uint256 public immutable endTime;
    bool public finalized;
    uint256 public totalRaised;

    mapping(address => uint256) public purchasedTokens;

    event TokensPurchased(address indexed buyer, uint256 amount, uint256 cost);
    event SaleFinalized(uint256 totalRaised);
    event TokensClaimed(address indexed claimer, uint256 amount);
    event UnsoldTokensWithdrawn(address indexed owner, uint256 amount);
    event PaymentTokensWithdrawn(address indexed owner, uint256 amount);

    constructor(
        address _saleToken,
        address _paymentToken,
        uint256 _tokenPrice,
        uint256 _totalTokensForSale,
        uint256 _minPurchase,
        uint256 _maxPurchase,
        uint256 _startTime,
        uint256 _endTime
    ) Ownable(msg.sender) {
        require(_saleToken != address(0) && _paymentToken != address(0), "Invalid token addresses");
        require(_tokenPrice > 0, "Invalid token price");
        require(_totalTokensForSale > 0, "Invalid total tokens");
        require(_minPurchase > 0 && _maxPurchase >= _minPurchase, "Invalid purchase limits");
        require(_startTime > block.timestamp && _endTime > _startTime, "Invalid time range");

        saleToken = IERC20(_saleToken);
        paymentToken = IERC20(_paymentToken);
        tokenPrice = _tokenPrice;
        totalTokensForSale = _totalTokensForSale;
        minPurchase = _minPurchase;
        maxPurchase = _maxPurchase;
        startTime = _startTime;
        endTime = _endTime;
    }

    function buyTokens(uint256 paymentAmount) external {
        require(block.timestamp >= startTime && block.timestamp <= endTime, "Sale not active");
        require(paymentAmount >= minPurchase && paymentAmount <= maxPurchase, "Invalid amount");

        uint256 tokensToBuy = (paymentAmount * 1e18) / tokenPrice;

        uint256 totalTokensSold = ((totalRaised + paymentAmount) * 1e18) / tokenPrice;
        require(totalTokensSold <= totalTokensForSale, "Exceeds total tokens");

        require(paymentToken.transferFrom(msg.sender, address(this), paymentAmount), "Payment transfer failed");
        purchasedTokens[msg.sender] += tokensToBuy;
        totalRaised += paymentAmount;

        emit TokensPurchased(msg.sender, tokensToBuy, paymentAmount);
    }


    function finalizeSale() external onlyOwner {
        require(block.timestamp > endTime, "Sale not ended");
        require(!finalized, "Already finalized");
        finalized = true;
        emit SaleFinalized(totalRaised);
    }

    function claimTokens() external {
        require(finalized, "Sale not finalized");
        uint256 amount = purchasedTokens[msg.sender];
        require(amount > 0, "No tokens to claim");

        purchasedTokens[msg.sender] = 0;
        require(saleToken.transfer(msg.sender, amount), "Token transfer failed");
        emit TokensClaimed(msg.sender, amount);
    }

    function withdrawUnsoldTokens() external onlyOwner {
        require(finalized, "Sale not finalized");
        // Calculate unsold tokens: totalTokensForSale - tokens sold
        uint256 tokensSold = totalRaised * 1e18 / tokenPrice;
        uint256 unsold = totalTokensForSale > tokensSold ? totalTokensForSale - tokensSold : 0;
        if (unsold > 0) {
            require(saleToken.transfer(owner(), unsold), "Token transfer failed");
            emit UnsoldTokensWithdrawn(owner(), unsold);
        }
    }

    function withdrawPaymentTokens() external onlyOwner {
        require(finalized, "Sale not finalized");
        uint256 balance = paymentToken.balanceOf(address(this));
        require(balance > 0, "No payment tokens to withdraw");
        require(paymentToken.transfer(owner(), balance), "Payment transfer failed");
        emit PaymentTokensWithdrawn(owner(), balance);
    }
}