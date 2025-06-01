const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Launchpad", function () {
  let deployer, user, saleToken, paymentToken, launchpad;
  let startTime, endTime;

  beforeEach(async function () {
    [deployer, user] = await ethers.getSigners();

    // Use the custom ERC20 contract
    const ERC20 = await ethers.getContractFactory("ERC20");
    saleToken = await ERC20.deploy("Sale Token", "SLT", ethers.utils.parseEther("1000000"));
    paymentToken = await ERC20.deploy("Token A", "TKA", ethers.utils.parseEther("1000000"));

    startTime = Math.floor(Date.now() / 1000) + 1000;
    endTime = startTime + 3600;
    const Launchpad = await ethers.getContractFactory("Launchpad");
    launchpad = await Launchpad.deploy(
      await saleToken.getAddress(),
      await paymentToken.getAddress(),
      ethers.utils.parseEther("0.01"),
      ethers.utils.parseEther("100000"),
      ethers.utils.parseEther("10"),
      ethers.utils.parseEther("1000"),
      startTime,
      endTime
    );

    await saleToken.transfer(await launchpad.getAddress(), ethers.utils.parseEther("100000"));
  });

  it("should allow buying tokens", async function () {
    await ethers.provider.send("evm_setNextBlockTimestamp", [startTime]);
    await ethers.provider.send("evm_mine");

    await paymentToken.transfer(user.address, ethers.utils.parseEther("100"));
    await paymentToken.connect(user).approve(await launchpad.getAddress(), ethers.utils.parseEther("100"));

    await launchpad.connect(user).buyTokens(ethers.utils.parseEther("50"));
    const purchased = await launchpad.purchasedTokens(user.address);
    expect(purchased).to.equal(ethers.utils.parseEther("5000"));
    expect(await launchpad.totalRaised()).to.equal(ethers.utils.parseEther("50"));
  });

  it("should prevent buying before sale starts", async function () {
    await expect(
      launchpad.buyTokens(ethers.utils.parseEther("50"))
    ).to.be.revertedWith("Sale not active");
  });

  it("should allow finalization and claiming tokens", async function () {
    await ethers.provider.send("evm_setNextBlockTimestamp", [startTime]);
    await ethers.provider.send("evm_mine");

    await paymentToken.transfer(user.address, ethers.utils.parseEther("100"));
    await paymentToken.connect(user).approve(await launchpad.getAddress(), ethers.utils.parseEther("100"));
    await launchpad.connect(user).buyTokens(ethers.utils.parseEther("50"));

    await ethers.provider.send("evm_setNextBlockTimestamp", [endTime + 1]);
    await ethers.provider.send("evm_mine");

    await launchpad.finalizeSale();
    expect(await launchpad.finalized()).to.be.true;

    await launchpad.connect(user).claimTokens();
    const balance = await saleToken.balanceOf(user.address);
    expect(balance).to.equal(ethers.utils.parseEther("5000"));
  });

  it("should allow owner to withdraw unsold tokens", async function () {
    await ethers.provider.send("evm_setNextBlockTimestamp", [endTime + 1]);
    await ethers.provider.send("evm_mine");

    await launchpad.finalizeSale();

    const initialBalance = await saleToken.balanceOf(deployer.address);
    await launchpad.withdrawUnsoldTokens();
    const finalBalance = await saleToken.balanceOf(deployer.address);
    expect(finalBalance.sub(initialBalance)).to.equal(ethers.utils.parseEther("100000"));
  });
});