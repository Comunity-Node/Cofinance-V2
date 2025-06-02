const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CoFinanceFactory", function () {
  let factory, deployer, user1;
  let tokenA, tokenB, priceOracle, swapMath;

  beforeEach(async function () {
    [deployer, user1] = await ethers.getSigners();

    // Deploy tokens
    const ERC20 = await ethers.getContractFactory("GovernanceToken");
    tokenA = await ERC20.deploy("Token A", "TKA", ethers.parseEther("1000000"));
    await tokenA.waitForDeployment();

    tokenB = await ERC20.deploy("Token B", "TKB", ethers.parseEther("1000000"));
    await tokenB.waitForDeployment();

    // Deploy price oracle
    const PriceOracle = await ethers.getContractFactory("CustomPriceOracle");
    priceOracle = await PriceOracle.deploy(tokenA.target, tokenB.target);
    await priceOracle.waitForDeployment();

    // Deploy SwapMath library
    const SwapMathFactory = await ethers.getContractFactory("SwapMath");
    swapMath = await SwapMathFactory.deploy();
    await swapMath.waitForDeployment();

    // Deploy factory
    const Factory = await ethers.getContractFactory("CoFinanceFactory", {
      libraries: {
        SwapMath: swapMath.target,
      },
    });
    factory = await Factory.deploy();
    await factory.waitForDeployment();
  });

  it("should deploy factory with correct owner", async function () {
    expect(await factory.owner()).to.equal(deployer.address);
  });

  it("should create a new pool successfully", async function () {
    const tx = await factory.connect(deployer).createPool(
      tokenA.target,
      tokenB.target,
      "LiquidityToken",
      "LPT",
      priceOracle.target
    );
    const receipt = await tx.wait();

    // Check emitted event
    const event = receipt.logs.find((e) => e.eventName === "PoolCreated");
    expect(event).to.not.be.undefined;

    const [poolAddress, token0, token1, liquidityToken] = event.args;
    expect(token0).to.equal(tokenA.target < tokenB.target ? tokenA.target : tokenB.target);
    expect(token1).to.equal(tokenA.target < tokenB.target ? tokenB.target : tokenA.target);
    expect(poolAddress).to.be.properAddress;
    expect(liquidityToken).to.be.properAddress;
    expect(await factory.pools(token0, token1)).to.equal(poolAddress);
    const allPools = await factory.getAllPools();
    expect(allPools).to.include(poolAddress);
  });

  it("should allow non-owner to create a pool", async function () {
    const tx = await factory.connect(user1).createPool(
      tokenA.target,
      tokenB.target,
      "LiquidityToken",
      "LPT",
      priceOracle.target
    );
    const receipt = await tx.wait();

    // Check emitted event
    const event = receipt.logs.find((e) => e.eventName === "PoolCreated");
    expect(event).to.not.be.undefined;

    const [poolAddress, token0, token1, liquidityToken] = event.args;
    expect(token0).to.equal(tokenA.target < tokenB.target ? tokenA.target : tokenB.target);
    expect(token1).to.equal(tokenA.target < tokenB.target ? tokenB.target : tokenA.target);
    expect(poolAddress).to.be.properAddress;
    expect(liquidityToken).to.be.properAddress;
    expect(await factory.pools(token0, token1)).to.equal(poolAddress);
    const allPools = await factory.getAllPools();
    expect(allPools).to.include(poolAddress);
  });

  it("should revert if creating pool with identical tokens", async function () {
    await expect(
      factory.connect(deployer).createPool(
        tokenA.target,
        tokenA.target,
        "LiquidityToken",
        "LPT",
        priceOracle.target
      )
    ).to.be.revertedWith("Identical tokens");
  });

  it("should revert if creating pool with zero address", async function () {
    await expect(
      factory.connect(deployer).createPool(
        ethers.ZeroAddress,
        tokenB.target,
        "LiquidityToken",
        "LPT",
        priceOracle.target
      )
    ).to.be.revertedWith("Zero address");
  });

  it("should revert if pool already exists", async function () {
    await factory.connect(deployer).createPool(
      tokenA.target,
      tokenB.target,
      "LiquidityToken",
      "LPT",
      priceOracle.target
    );
    // Try creating again with same tokens (order doesn't matter)
    await expect(
      factory.connect(deployer).createPool(
        tokenB.target,
        tokenA.target,
        "LiquidityToken",
        "LPT",
        priceOracle.target
      )
    ).to.be.revertedWith("Pool exists");
  });
});