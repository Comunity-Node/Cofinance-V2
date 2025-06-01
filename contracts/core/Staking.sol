// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Staking {
    using SafeERC20 for IERC20;

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;
    mapping(address => uint256) public stakedBalances;
    mapping(address => uint256) public stakingDurations;
    mapping(address => uint256) public stakingTimestamps;
    uint256 public totalStaked;

    event Staked(address indexed staker, uint256 amount, uint256 duration);
    event Unstaked(address indexed staker, uint256 amount);
    event RewardClaimed(address indexed staker, uint256 amount);

    constructor(address _stakingToken, address _rewardToken) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
    }

    function stake(address staker, uint256 amount, uint256 duration) external {
        require(amount > 0, "Amount must be > 0");
        require(duration == 7 days || duration == 14 days || duration == 21 days, "Invalid duration");

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        stakedBalances[staker] += amount;
        stakingDurations[staker] = duration;
        stakingTimestamps[staker] = block.timestamp;
        totalStaked += amount;

        emit Staked(staker, amount, duration);
    }

    function unstake(address staker, uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        require(stakedBalances[staker] >= amount, "Insufficient balance");

        stakedBalances[staker] -= amount;
        totalStaked -= amount;
        stakingToken.safeTransfer(staker, amount);

        emit Unstaked(staker, amount);
    }

    function claimRewards(address staker) external {
        uint256 reward = calculateReward(staker);
        require(reward > 0, "No rewards");
        rewardToken.safeTransfer(staker, reward);
        stakingTimestamps[staker] = block.timestamp; 
        emit RewardClaimed(staker, reward);
    }

    function calculateReward(address staker) public view returns (uint256) {
        uint256 duration = block.timestamp - stakingTimestamps[staker];
        uint256 rewardRate = stakingDurations[staker] == 7 days ? 20 :
                            stakingDurations[staker] == 14 days ? 30 :
                            stakingDurations[staker] == 21 days ? 50 : 0;
        return stakedBalances[staker] * rewardRate * duration / 365 / 100;
    }
}