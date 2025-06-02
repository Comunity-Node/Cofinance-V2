// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Launchpad is Ownable {
    IERC20 public saleToken;
    IERC20 public paymentToken;
    uint256 public tokenPrice;
    uint256 public totalTokensForSale;
    uint256 public minPurchase;
    uint256 public maxPurchase;
    uint256 public startTime;
    uint256 public endTime;
    bool public finalized;
    uint256 public totalRaised;

    mapping(address => uint256) public purchasedTokens;

    event TokensPurchased(address indexed buyer, uint256 amount, uint256 cost);
    event SaleFinalized(uint256 totalRaised);
    event TokensClaimed(address indexed claimer, uint256 amount);

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
        require(totalRaised + paymentAmount <= totalTokensForSale * tokenPrice / 1e18, "Exceeds total tokens");

        paymentToken.transferFrom(msg.sender, address(this), paymentAmount);
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
        saleToken.transfer(msg.sender, amount);
        emit TokensClaimed(msg.sender, amount);
    }

    function withdrawUnsoldTokens() external onlyOwner {
        require(finalized, "Sale not finalized");
        uint256 unsold = saleToken.balanceOf(address(this));
        saleToken.transfer(owner(), unsold);
    }
}