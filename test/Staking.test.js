const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Staking", function () {
  let deployer, user1, user2;
  let stakingToken, rewardToken, priceOracle, staking;

  beforeEach(async function () {
    [deployer, user1, user2] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("GovernanceToken");
    stakingToken = await ERC20.deploy("Staking Token", "STK", ethers.parseEther("1000000"));
    rewardToken = await ERC20.deploy("Reward Token", "RWD", ethers.parseEther("1000000"));

    const CustomPriceOracle = await ethers.getContractFactory("CustomPriceOracle");
    priceOracle = await CustomPriceOracle.deploy(await stakingToken.getAddress(), await rewardToken.getAddress());

    const Staking = await ethers.getContractFactory("Staking");
    staking = await Staking.deploy(
      await stakingToken.getAddress(),
      await rewardToken.getAddress(),
      await priceOracle.getAddress()
    );

    // Fund users and staking contract
    await stakingToken.transfer(user1.address, ethers.parseEther("1000"));
    await stakingToken.transfer(user2.address, ethers.parseEther("1000"));
    await rewardToken.transfer(await staking.getAddress(), ethers.parseEther("10000"));
  });

  describe("Stake", function () {
    it("should stake tokens successfully", async function () {
      await stakingToken.connect(user1).approve(await staking.getAddress(), ethers.parseEther("100"));
      await expect(staking.connect(user1).stake(ethers.parseEther("100")))
        .to.emit(staking, "Staked")
        .withArgs(user1.address, ethers.parseEther("100"));

      expect(await staking.stakedBalance(user1.address)).to.equal(ethers.parseEther("100"));
      expect(await staking.totalStaked()).to.equal(ethers.parseEther("100"));
      expect(await stakingToken.balanceOf(user1.address)).to.equal(ethers.parseEther("900"));
    });

    it("should revert with zero stake", async function () {
      await expect(staking.connect(user1).stake(0)).to.be.revertedWith("Invalid amount");
    });
  });

  describe("Withdraw", function () {
    beforeEach(async function () {
      await stakingToken.connect(user1).approve(await staking.getAddress(), ethers.parseEther("100"));
      await staking.connect(user1).stake(ethers.parseEther("100"));
    });

    it("should withdraw staked tokens", async function () {
      await expect(staking.connect(user1).withdraw(ethers.parseEther("50")))
        .to.emit(staking, "Withdrawn")
        .withArgs(user1.address, ethers.parseEther("50"));

      expect(await staking.stakedBalance(user1.address)).to.equal(ethers.parseEther("50"));
      expect(await staking.totalStaked()).to.equal(ethers.parseEther("50"));
      expect(await stakingToken.balanceOf(user1.address)).to.equal(ethers.parseEther("950"));
    });

    it("should revert with excessive withdraw", async function () {
      await expect(staking.connect(user1).withdraw(ethers.parseEther("101"))).to.be.revertedWith("Invalid amount");
    });
  });

  describe("Claim Rewards", function () {
    beforeEach(async function () {
      await stakingToken.connect(user1).approve(await staking.getAddress(), ethers.parseEther("100"));
      await staking.connect(user1).stake(ethers.parseEther("100"));
    });

    it("should claim rewards after time", async function () {
      await ethers.provider.send("evm_increaseTime", [3600]); // 1 hour
      await ethers.provider.send("evm_mine");

      await expect(staking.connect(user1).claimRewards())
        .to.emit(staking, "RewardClaimed")
        .withArgs(user1.address, ethers.parseEther("3600")); // 100 * 3600 * 1000 / 1e18

      expect(await rewardToken.balanceOf(user1.address)).to.equal(ethers.parseEther("3600"));
      expect(await staking.rewards(user1.address)).to.equal(0);
    });

    it("should revert with no rewards", async function () {
      await expect(staking.connect(user2).claimRewards()).to.be.revertedWith("No rewards");
    });
  });
});