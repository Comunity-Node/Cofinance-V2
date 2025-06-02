const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CoFinanceRouter", function () {
  let factory, router, deployer, user1, tokenA, tokenB, priceOracle, swapMath, tickMath, liquidityMath;
  let pool, lendingPool, liquidityToken, liquidationLogic;

  beforeEach(async function () {
    [deployer, user1] = await ethers.getSigners();

    // Deploy libraries
    const SwapMathFactory = await ethers.getContractFactory("SwapMath");
    swapMath = await SwapMathFactory.deploy();
    await swapMath.waitForDeployment();

    const TickMathFactory = await ethers.getContractFactory("TickMath");
    tickMath = await TickMathFactory.deploy();
    await tickMath.waitForDeployment();

    const LiquidityMathFactory = await ethers.getContractFactory("LiquidityMath");
    liquidityMath = await LiquidityMathFactory.deploy();
    await liquidityMath.waitForDeployment();

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
    await priceOracle.setPrices(ethers.parseEther("1"), ethers.parseEther("1")); // 1:1 price

    // Deploy factory
   const Factory = await ethers.getContractFactory("CoFinanceFactory", {
      libraries: {
        SwapMath: swapMath.target,
      },
    });

    factory = await Factory.deploy();
    await factory.waitForDeployment();

    // Deploy liquidation logic with a placeholder lending pool address
    const LiquidationLogic = await ethers.getContractFactory("LiquidationLogic");
    liquidationLogic = await LiquidationLogic.deploy(ethers.ZeroAddress, priceOracle.target);
    await liquidationLogic.waitForDeployment();

    // Deploy lending pool with correct liquidation logic
    const LendingPool = await ethers.getContractFactory("LendingPool");
    lendingPool = await LendingPool.deploy(
      tokenA.target,
      tokenB.target,
      priceOracle.target,
      liquidationLogic.target
    );
    await lendingPool.waitForDeployment();

    // Update factory lending pool mapping
    await factory.connect(deployer).createLendingPool(
      tokenA.target,
      tokenB.target,
      priceOracle.target,
      liquidationLogic.target
    );

    // Deploy router
    const Router = await ethers.getContractFactory("CoFinanceRouter");
    router = await Router.deploy(factory.target);
    await router.waitForDeployment();

    // Create a pool
    const tx = await factory.connect(deployer).createPool(
      tokenA.target,
      tokenB.target,
      "LiquidityToken",
      "LPT",
      priceOracle.target
    );
    const receipt = await tx.wait();
    const event = receipt.logs.find((e) => e.eventName === "PoolCreated");
    pool = await ethers.getContractAt("CoFinancePool", event.args[0]);
    liquidityToken = await ethers.getContractAt("LiquidityToken", event.args[3]);

    // Distribute tokens and approve
    await tokenA.transfer(user1.address, ethers.parseEther("10000"));
    await tokenB.transfer(user1.address, ethers.parseEther("10000"));
    await tokenA.transfer(pool.target, ethers.parseEther("1000"));
    await tokenB.transfer(pool.target, ethers.parseEther("1000"));
    await tokenA.transfer(lendingPool.target, ethers.parseEther("1000"));
    await tokenB.transfer(lendingPool.target, ethers.parseEther("1000"));

    await tokenA.connect(user1).approve(router.target, ethers.parseEther("10000"));
    await tokenB.connect(user1).approve(router.target, ethers.parseEther("10000"));
    await tokenA.connect(user1).approve(pool.target, ethers.parseEther("10000"));
    await tokenB.connect(user1).approve(pool.target, ethers.parseEther("10000"));
    await tokenA.connect(user1).approve(lendingPool.target, ethers.parseEther("10000"));
    await tokenB.connect(user1).approve(lendingPool.target, ethers.parseEther("10000"));
  });

  it("should deploy router with correct factory address", async function () {
    expect(await router.factory()).to.equal(factory.target);
  });

  it("should add liquidity to a pool", async function () {
    const amountA = ethers.parseEther("100");
    const amountB = ethers.parseEther("100");
    const initialBalance = await liquidityToken.balanceOf(user1.address);

    await expect(
      router.connect(user1).addLiquidity(
        tokenA.target,
        tokenB.target,
        amountA,
        amountB,
        -887272,
        887272
      )
    )
      .to.emit(pool, "LiquidityAdded")
      .withArgs(user1.address, amountA, amountB, amountA + amountB);

    expect(await liquidityToken.balanceOf(user1.address)).to.equal(initialBalance + (amountA + amountB));
    expect(await pool.liquidity(user1.address)).to.equal(amountA + amountB);
  });

  it("should revert adding liquidity to non-existent pool", async function () {
    const tokenC = await (await ethers.getContractFactory("GovernanceToken")).deploy(
      "Token C",
      "TKC",
      ethers.parseEther("1000000")
    );
    await tokenC.waitForDeployment();
    await tokenC.connect(user1).approve(router.target, ethers.parseEther("10000"));

    await expect(
      router.connect(user1).addLiquidity(
        tokenA.target,
        tokenC.target,
        ethers.parseEther("100"),
        ethers.parseEther("100"),
        -887272,
        887272
      )
    ).to.be.revertedWith("Pool does not exist");
  });

  it("should swap tokens", async function () {
    await router.connect(user1).addLiquidity(
      tokenA.target,
      tokenB.target,
      ethers.parseEther("100"),
      ethers.parseEther("100"),
      -887272,
      887272
    );

    const amountIn = ethers.parseEther("10");
    const minAmountOut = ethers.parseEther("5");
    const initialBalanceB = await tokenB.balanceOf(user1.address);

    await expect(
      router.connect(user1).swap(
        tokenA.target,
        tokenB.target,
        tokenA.target,
        amountIn,
        minAmountOut
      )
    )
      .to.emit(pool, "Swap")
      .withArgs(user1.address, tokenA.target, amountIn, amountIn);

    expect(await tokenB.balanceOf(user1.address)).to.equal(initialBalanceB + amountIn);
    expect(await tokenA.balanceOf(user1.address)).to.equal(ethers.parseEther("10000") - amountIn);
  });

  it("should revert swap with invalid token", async function () {
    const tokenC = await (await ethers.getContractFactory("GovernanceToken")).deploy(
      "Token C",
      "TKC",
      ethers.parseEther("1000000")
    );
    await tokenC.waitForDeployment();

    await expect(
      router.connect(user1).swap(
        tokenA.target,
        tokenB.target,
        tokenC.target,
        ethers.parseEther("10"),
        ethers.parseEther("5")
      )
    ).to.be.revertedWith("Invalid input token");
  });

  it("should revert swap with insufficient output amount", async function () {
    await router.connect(user1).addLiquidity(
      tokenA.target,
      tokenB.target,
      ethers.parseEther("100"),
      ethers.parseEther("100"),
      -887272,
      887272
    );

    await expect(
      router.connect(user1).swap(
        tokenA.target,
        tokenB.target,
        tokenA.target,
        ethers.parseEther("10"),
        ethers.parseEther("20")
      )
    ).to.be.revertedWith("Insufficient output amount");
  });

  it("should borrow with collateral", async function () {
    const borrowAmount = ethers.parseEther("100");
    const collateralAmount = ethers.parseEther("150"); // 150% collateral ratio
    const initialBalanceA = await tokenA.balanceOf(user1.address);
    const initialBalanceB = await tokenB.balanceOf(user1.address);

    await expect(
      router.connect(user1).borrow(tokenA.target, borrowAmount, tokenB.target, collateralAmount)
    )
      .to.emit(lendingPool, "Borrow")
      .withArgs(user1.address, tokenA.target, borrowAmount, tokenB.target, collateralAmount);

    expect(await lendingPool.borrowed(user1.address)).to.equal(borrowAmount);
    expect(await lendingPool.collateral(user1.address)).to.equal(collateralAmount);
    expect(await lendingPool.borrowedToken(user1.address)).to.equal(tokenA.target);
    expect(await lendingPool.collateralToken(user1.address)).to.equal(tokenB.target);
    expect(await tokenA.balanceOf(user1.address)).to.equal(initialBalanceA + borrowAmount);
    expect(await tokenB.balanceOf(user1.address)).to.equal(initialBalanceB - collateralAmount);
  });

  it("should revert borrow with non-existent lending pool", async function () {
    const tokenC = await (await ethers.getContractFactory("GovernanceToken")).deploy(
      "Token C",
      "TKC",
      ethers.parseEther("1000000")
    );
    await tokenC.waitForDeployment();
    await tokenC.connect(user1).approve(router.target, ethers.parseEther("10000"));

    await expect(
      router.connect(user1).borrow(tokenA.target, ethers.parseEther("100"), tokenC.target, ethers.parseEther("150"))
    ).to.be.revertedWith("Lending pool does not exist");
  });

  it("should repay borrowed amount", async function () {
    const borrowAmount = ethers.parseEther("100");
    const collateralAmount = ethers.parseEther("150");
    await router.connect(user1).borrow(tokenA.target, borrowAmount, tokenB.target, collateralAmount);

    await router.connect(user1).repay(tokenA.target, tokenB.target, borrowAmount);

    expect(await lendingPool.borrowed(user1.address)).to.equal(0);
    expect(await lendingPool.collateral(user1.address)).to.equal(collateralAmount);
    expect(await lendingPool.borrowedToken(user1.address)).to.equal(ethers.ZeroAddress);
    expect(await lendingPool.collateralToken(user1.address)).to.equal(ethers.ZeroAddress);
  });

  it("should add collateral", async function () {
    const borrowAmount = ethers.parseEther("100");
    const collateralAmount = ethers.parseEther("150");
    const additionalCollateral = ethers.parseEther("50");
    await router.connect(user1).borrow(tokenA.target, borrowAmount, tokenB.target, collateralAmount);

    await router.connect(user1).addCollateral(tokenA.target, tokenB.target, additionalCollateral);

    expect(await lendingPool.collateral(user1.address)).to.equal(collateralAmount + additionalCollateral);
  });

  it("should withdraw collateral", async function () {
    const borrowAmount = ethers.parseEther("100");
    const collateralAmount = ethers.parseEther("200"); // Extra collateral to allow withdrawal
    const withdrawAmount = ethers.parseEther("25"); // Withdraw 25, leaving 175 (>150)
    await router.connect(user1).borrow(tokenA.target, borrowAmount, tokenB.target, collateralAmount);

    const initialBalanceB = await tokenB.balanceOf(user1.address);
    await router.connect(user1).withdrawCollateral(tokenA.target, tokenB.target, withdrawAmount);

    expect(await lendingPool.collateral(user1.address)).to.equal(collateralAmount - withdrawAmount);
    expect(await tokenB.balanceOf(user1.address)).to.equal(initialBalanceB + withdrawAmount);
  });

  it("should revert withdraw with insufficient collateral", async function () {
    const borrowAmount = ethers.parseEther("100");
    const collateralAmount = ethers.parseEther("150");
    await router.connect(user1).borrow(tokenA.target, borrowAmount, tokenB.target, collateralAmount);

    await expect(
      router.connect(user1).withdrawCollateral(tokenA.target, tokenB.target, ethers.parseEther("100"))
    ).to.be.revertedWith("Insufficient collateral after withdrawal");
  });
});