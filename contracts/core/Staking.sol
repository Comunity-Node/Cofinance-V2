// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../oracle/CustomPriceOracle.sol";

contract Staking is Ownable {
    IERC20 public stakingToken;
    IERC20 public rewardToken;
    CustomPriceOracle public priceOracle;

    uint256 public rewardRate = 1000; // Rewards per second (scaled by 1e18)
    uint256 public totalStaked;
    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public lastUpdateTime;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);

    constructor(
        address _stakingToken,
        address _rewardToken,
        address _priceOracle
    ) Ownable(msg.sender) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        priceOracle = CustomPriceOracle(_priceOracle);
    }

    function stake(uint256 amount) external {
        require(amount > 0, "Invalid amount");
        updateRewards(msg.sender);

        stakingToken.transferFrom(msg.sender, address(this), amount);
        stakedBalance[msg.sender] += amount;
        totalStaked += amount;

        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0 && amount <= stakedBalance[msg.sender], "Invalid amount");
        updateRewards(msg.sender);

        stakedBalance[msg.sender] -= amount;
        totalStaked -= amount;
        stakingToken.transfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    function claimRewards() external {
        updateRewards(msg.sender);
        uint256 reward = rewards[msg.sender];
        require(reward > 0, "No rewards");

        rewards[msg.sender] = 0;
        rewardToken.transfer(msg.sender, reward);

        emit RewardClaimed(msg.sender, reward);
    }

    function updateRewards(address user) internal {
        uint256 timeDiff = block.timestamp - lastUpdateTime[user];
        rewards[user] += stakedBalance[user] * timeDiff * rewardRate / 1e18;
        lastUpdateTime[user] = block.timestamp;
    }

    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        rewardRate = _rewardRate;
    }
}