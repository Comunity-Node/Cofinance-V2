const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Launchpad", function () {
  let deployer, user1, user2;
  let saleToken, paymentToken, launchpad;
  let startTime, endTime;

  beforeEach(async function () {
    [deployer, user1, user2] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("GovernanceToken");
    saleToken = await ERC20.deploy("Sale Token", "SLT", ethers.parseEther("1000000"));
    await saleToken.waitForDeployment();
    paymentToken = await ERC20.deploy("Payment Token", "PTK", ethers.parseEther("1000000"));
    await paymentToken.waitForDeployment();

    startTime = Math.floor(Date.now() / 1000) + 1000;
    endTime = startTime + 3600;

    const Launchpad = await ethers.getContractFactory("Launchpad");
    launchpad = await Launchpad.deploy(
      saleToken.target,
      paymentToken.target,
      ethers.parseEther("0.01"), // 0.01 paymentToken per saleToken
      ethers.parseEther("100000"), // 100,000 saleTokens
      ethers.parseEther("10"), // min 10 paymentToken
      ethers.parseEther("1000"), // max 1000 paymentToken
      startTime,
      endTime
      // vesting.target // Uncomment if vesting is needed
    );
    await launchpad.waitForDeployment();

    await saleToken.transfer(launchpad.target, ethers.parseEther("100000"));
    await paymentToken.transfer(user1.address, ethers.parseEther("2000"));
    await paymentToken.transfer(user2.address, ethers.parseEther("2000"));
  });

  describe("Buy Tokens", function () {
    beforeEach(async function () {
      await ethers.provider.send("evm_setNextBlockTimestamp", [startTime]);
      await ethers.provider.send("evm_mine");
    });

    it("should buy tokens successfully", async function () {
      await paymentToken.connect(user1).approve(launchpad.target, ethers.parseEther("50"));
      await expect(launchpad.connect(user1).buyTokens(ethers.parseEther("50")))
        .to.emit(launchpad, "TokensPurchased")
        .withArgs(user1.address, ethers.parseEther("5000"), ethers.parseEther("50"));

      expect(await launchpad.purchasedTokens(user1.address)).to.equal(ethers.parseEther("5000"));
      expect(await launchpad.totalRaised()).to.equal(ethers.parseEther("50"));
    });

    it("should revert with amount below minimum", async function () {
      await paymentToken.connect(user1).approve(launchpad.target, ethers.parseEther("5"));
      await expect(
        launchpad.connect(user1).buyTokens(ethers.parseEther("5"))
      ).to.be.revertedWith("Invalid amount");
    });

    it("should revert with amount above maximum", async function () {
      await paymentToken.connect(user1).approve(launchpad.target, ethers.parseEther("1001"));
      await expect(
        launchpad.connect(user1).buyTokens(ethers.parseEther("1001"))
      ).to.be.revertedWith("Invalid amount");
    });

    it("should revert if sale not active", async function () {
      await ethers.provider.send("evm_setNextBlockTimestamp", [startTime - 1001]);
      await ethers.provider.send("evm_mine");
      await paymentToken.connect(user1).approve(launchpad.target, ethers.parseEther("50"));
      await expect(
        launchpad.connect(user1).buyTokens(ethers.parseEther("50"))
      ).to.be.revertedWith("Sale not active");
    });
  });

  describe("Finalize and Claim", function () {
    beforeEach(async function () {
      await ethers.provider.send("evm_setNextBlockTimestamp", [startTime]);
      await ethers.provider.send("evm_mine");
      await paymentToken.connect(user1).approve(launchpad.target, ethers.parseEther("50"));
      await launchpad.connect(user1).buyTokens(ethers.parseEther("50"));
      await ethers.provider.send("evm_setNextBlockTimestamp", [endTime + 1]);
      await ethers.provider.send("evm_mine");
    });

    it("should finalize sale", async function () {
      await expect(launchpad.connect(deployer).finalizeSale())
        .to.emit(launchpad, "SaleFinalized")
        .withArgs(ethers.parseEther("50"));
      expect(await launchpad.finalized()).to.be.true;
    });

    it("should claim tokens after finalization", async function () {
      await launchpad.connect(deployer).finalizeSale();
      await expect(launchpad.connect(user1).claimTokens())
        .to.emit(launchpad, "TokensClaimed")
        .withArgs(user1.address, ethers.parseEther("5000"));
      expect(await saleToken.balanceOf(user1.address)).to.equal(ethers.parseEther("5000"));
      expect(await launchpad.purchasedTokens(user1.address)).to.equal(0);
    });

    it("should revert claim before finalization", async function () {
      await expect(launchpad.connect(user1).claimTokens()).to.be.revertedWith("Sale not finalized");
    });
  });

  describe("Withdraw Unsold Tokens", function () {
    beforeEach(async function () {
      await ethers.provider.send("evm_setNextBlockTimestamp", [startTime]);
      await ethers.provider.send("evm_mine");
      await paymentToken.connect(user1).approve(launchpad.target, ethers.parseEther("50"));
      await launchpad.connect(user1).buyTokens(ethers.parseEther("50"));
      await ethers.provider.send("evm_setNextBlockTimestamp", [endTime + 1]);
      await ethers.provider.send("evm_mine");
      await launchpad.connect(deployer).finalizeSale();
    });

    it("should withdraw unsold tokens", async function () {
      const initialBalance = await saleToken.balanceOf(deployer.address);
      await expect(launchpad.connect(deployer).withdrawUnsoldTokens())
        .to.emit(launchpad, "UnsoldTokensWithdrawn")
        .withArgs(deployer.address, ethers.parseEther("95000"));
      const finalBalance = await saleToken.balanceOf(deployer.address);
      expect(finalBalance.sub(initialBalance)).to.equal(ethers.parseEther("95000")); // 100,000 - 5,000
    });

    it("should revert if not owner", async function () {
      await expect(launchpad.connect(user1).withdrawUnsoldTokens()).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("should withdraw payment tokens", async function () {
      const initialBalance = await paymentToken.balanceOf(deployer.address);
      await expect(launchpad.connect(deployer).withdrawPaymentTokens())
        .to.emit(launchpad, "PaymentTokensWithdrawn")
        .withArgs(deployer.address, ethers.parseEther("50"));
      const finalBalance = await paymentToken.balanceOf(deployer.address);
      expect(finalBalance.sub(initialBalance)).to.equal(ethers.parseEther("50"));
    });
  });

  // Optional: Vesting tests (uncomment if vesting is integrated)
  /*
  describe("Vesting Integration", function () {
    let vesting;
    beforeEach(async function () {
      const Vesting = await ethers.getContractFactory("Vesting");
      vesting = await Vesting.deploy(saleToken.target, 3600); // 1 hour vesting
      await vesting.waitForDeployment();

      // Redeploy launchpad with vesting
      const Launchpad = await ethers.getContractFactory("Launchpad");
      launchpad = await Launchpad.deploy(
        saleToken.target,
        paymentToken.target,
        ethers.parseEther("0.01"),
        ethers.parseEther("100000"),
        ethers.parseEther("10"),
        ethers.parseEther("1000"),
        startTime,
        endTime,
        vesting.target
      );
      await launchpad.waitForDeployment();

      await saleToken.transfer(launchpad.target, ethers.parseEther("100000"));
      await paymentToken.transfer(user1.address, ethers.parseEther("2000"));
      await vesting.transferOwnership(launchpad.target); // Allow launchpad to vest tokens
      await ethers.provider.send("evm_setNextBlockTimestamp", [startTime]);
      await ethers.provider.send("evm_mine");
    });

    it("should vest tokens on purchase", async function () {
      await paymentToken.connect(user1).approve(launchpad.target, ethers.parseEther("50"));
      await expect(launchpad.connect(user1).buyTokens(ethers.parseEther("50")))
        .to.emit(vesting, "Vested")
        .withArgs(user1.address, ethers.parseEther("5000"));
      expect(await vesting.vestedAmounts(user1.address)).to.equal(ethers.parseEther("5000"));
      expect(await launchpad.purchasedTokens(user1.address)).to.equal(0);
    });

    it("should claim vested tokens over time", async function () {
      await paymentToken.connect(user1).approve(launchpad.target, ethers.parseEther("50"));
      await launchpad.connect(user1).buyTokens(ethers.parseEther("50"));
      await ethers.provider.send("evm_increaseTime", [1800]); // Half vesting period
      await ethers.provider.send("evm_mine");
      await expect(vesting.connect(user1).claim())
        .to.emit(vesting, "Claimed")
        .withArgs(user1.address, ethers.parseEther("2500")); // Half vested
      expect(await saleToken.balanceOf(user1.address)).to.equal(ethers.parseEther("2500"));
    });
  });
  */
});