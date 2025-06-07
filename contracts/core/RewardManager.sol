// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interface/ILiquidityToken.sol";

contract RewardManager is Ownable, ReentrancyGuard {
    IERC20 public immutable token0;
    IERC20 public immutable token1;
    ILiquidityToken public immutable liquidityToken;
    address public immutable platformOwner;

    uint256 public platformFeesToken0;
    uint256 public platformFeesToken1;
    uint256 public platformInterestToken0;
    uint256 public platformInterestToken1;
    mapping(address => uint256) public userFeesToken0;
    mapping(address => uint256) public userFeesToken1;
    mapping(address => uint256) public userInterestToken0;
    mapping(address => uint256) public userInterestToken1;
    mapping(address => uint256) public lastClaimedLiquidity;

    uint256 public constant PLATFORM_FEE = 10; // 10%

    event RewardsAllocated(address indexed user, uint256 fee0, uint256 fee1, uint256 interest0, uint256 interest1);
    event RewardsClaimed(address indexed user, uint256 fee0, uint256 fee1, uint256 interest0, uint256 interest1);
    event PlatformFeesClaimed(address indexed owner, uint256 fee0, uint256 fee1, uint256 interest0, uint256 interest1);

    constructor(
        address _token0,
        address _token1,
        address _liquidityToken,
        address _platformOwner
    ) Ownable(msg.sender) {
        require(_token0 != address(0) && _token1 != address(0), "Invalid token addresses");
        require(_liquidityToken != address(0), "Invalid liquidity token address");
        require(_platformOwner != address(0), "Invalid platform owner address");
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        liquidityToken = ILiquidityToken(_liquidityToken);
        platformOwner = _platformOwner;
    }

    function allocateSwapFees(address user, uint256 fee0, uint256 fee1) external onlyOwner {
        require(user != address(0), "Invalid user address");
        uint256 totalSupply = liquidityToken.totalSupply();
        if (totalSupply == 0) return;

        uint256 userLiquidity = liquidityToken.balanceOf(user);
        if (userLiquidity == 0) return;

        uint256 userShare = (userLiquidity * 1e18) / totalSupply;
        uint256 platformFee0 = (fee0 * PLATFORM_FEE) / 100;
        uint256 platformFee1 = (fee1 * PLATFORM_FEE) / 100;
        uint256 userFee0 = ((fee0 - platformFee0) * userShare) / 1e18;
        uint256 userFee1 = ((fee1 - platformFee1) * userShare) / 1e18;

        platformFeesToken0 += platformFee0;
        platformFeesToken1 += platformFee1;
        userFeesToken0[user] += userFee0;
        userFeesToken1[user] += userFee1;

        lastClaimedLiquidity[user] = userLiquidity;
        emit RewardsAllocated(user, userFee0, userFee1, 0, 0);
    }

    function allocateInterest(address user, uint256 interest0, uint256 interest1) external onlyOwner {
        require(user != address(0), "Invalid user address");
        uint256 platformInterest0 = (interest0 * PLATFORM_FEE) / 100;
        uint256 platformInterest1 = (interest1 * PLATFORM_FEE) / 100;
        uint256 userInterest0 = interest0 - platformInterest0;
        uint256 userInterest1 = interest1 - platformInterest1;

        platformInterestToken0 += platformInterest0;
        platformInterestToken1 += platformInterest1;
        userInterestToken0[user] += userInterest0;
        userInterestToken1[user] += userInterest1;

        emit RewardsAllocated(user, 0, 0, userInterest0, userInterest1);
    }

    function claimRewards(address user) external nonReentrant {
        require(user != address(0), "Invalid user address");
        uint256 fee0 = userFeesToken0[user];
        uint256 fee1 = userFeesToken1[user];
        uint256 interest0 = userInterestToken0[user];
        uint256 interest1 = userInterestToken1[user];

        require(fee0 > 0 || fee1 > 0 || interest0 > 0 || interest1 > 0, "No rewards to claim");

        userFeesToken0[user] = 0;
        userFeesToken1[user] = 0;
        userInterestToken0[user] = 0;
        userInterestToken1[user] = 0;

        if (fee0 > 0) require(token0.transfer(user, fee0), "Token0 transfer failed");
        if (fee1 > 0) require(token1.transfer(user, fee1), "Token1 transfer failed");
        if (interest0 > 0) require(token0.transfer(user, interest0), "Token0 interest transfer failed");
        if (interest1 > 0) require(token1.transfer(user, interest1), "Token1 interest transfer failed");

        emit RewardsClaimed(user, fee0, fee1, interest0, interest1);
    }

    function claimPlatformFees() external nonReentrant {
        require(msg.sender == platformOwner, "Only platform owner");
        uint256 fee0 = platformFeesToken0;
        uint256 fee1 = platformFeesToken1;
        uint256 interest0 = platformInterestToken0;
        uint256 interest1 = platformInterestToken1;

        require(fee0 > 0 || fee1 > 0 || interest0 > 0 || interest1 > 0, "No platform fees to claim");

        platformFeesToken0 = 0;
        platformFeesToken1 = 0;
        platformInterestToken0 = 0;
        platformInterestToken1 = 0;

        if (fee0 > 0) require(token0.transfer(platformOwner, fee0), "Token0 transfer failed");
        if (fee1 > 0) require(token1.transfer(platformOwner, fee1), "Token1 transfer failed");
        if (interest0 > 0) require(token0.transfer(platformOwner, interest0), "Token0 interest transfer failed");
        if (interest1 > 0) require(token1.transfer(platformOwner, interest1), "Token1 interest transfer failed");

        emit PlatformFeesClaimed(platformOwner, fee0, fee1, interest0, interest1);
    }
}