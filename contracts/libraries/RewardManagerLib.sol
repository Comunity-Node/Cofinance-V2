// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library RewardManagerLib {
    struct RewardStorage {
        mapping(address => uint256) userRewards;
        uint256 totalRewardsToken0; 
        uint256 totalRewardsToken1; 
        uint256 lastUpdateTime; 
    }

    function allocateSwapFees(
        RewardStorage storage self,
        address user,
        uint256 fee0,
        uint256 fee1
    ) internal {
        self.userRewards[user] += fee0 + fee1;
        self.totalRewardsToken0 += fee0;
        self.totalRewardsToken1 += fee1;
        self.lastUpdateTime = block.timestamp;
    }

    function allocateInterest(
        RewardStorage storage self,
        address user,
        uint256 interest0,
        uint256 interest1
    ) internal {
        self.userRewards[user] += interest0 + interest1;
        self.totalRewardsToken0 += interest0;
        self.totalRewardsToken1 += interest1;
        self.lastUpdateTime = block.timestamp;
    }

    function claimRewards(
        RewardStorage storage self,
        address user
    ) internal returns (uint256 rewardAmount) {
        rewardAmount = self.userRewards[user];
        self.userRewards[user] = 0;
    }
}