const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CoFinanceRouter", function () {
  let factory, router, deployer, user1, tokenA, tokenB, priceOracle, swapMath, tickMath, liquidityMath;
  let pool, lendingPool, liquidityToken, liquidationLogic;

  beforeEach(async function () {
    [deployer, user1] = await ethers.getSigners();

    // Deploy SwapMath library
    const SwapMathFactory = await ethers.getContractFactory("SwapMath");
    swapMath = await SwapMathFactory.deploy();
    await swapMath.waitForDeployment();

    // Deploy TickMath library
    const TickMathFactory = await ethers.getContractFactory("TickMath");
    tickMath = await TickMathFactory.deploy();
    await tickMath.waitForDeployment();

    // Deploy LiquidityMath library
    const LiquidityMathFactory = await ethers.getContractFactory("LiquidityMath");
    liquidityMath = await LiquidityMathFactory.deploy();
    await liquidityMath.waitForDeployment();

    // Deploy ERC20 tokens
    const ERC20 = await ethers.getContractFactory("GovernanceToken");
    tokenA = await ERC20.deploy("Token A", "TKA", ethers.parseEther("1000000"));
    await tokenA.waitForDeployment();
    tokenB = await ERC20.deploy("Token B", "TKB", ethers.parseEther("1000000"));
    await tokenB.waitForDeployment();

    // Deploy PriceOracle
    const PriceOracle = await ethers.getContractFactory("CustomPriceOracle");
    priceOracle = await PriceOracle.deploy(tokenA.target, tokenB.target);
    await priceOracle.waitForDeployment();
    await priceOracle.setPrices(ethers.parseEther("1"), ethers.parseEther("1")); // 1:1 price

    // Deploy CoFinanceFactory with linked libraries
    const Factory = await ethers.getContractFactory("CoFinanceFactory", {
      libraries: {
        SwapMath: swapMath.target,
        LiquidityMath: liquidityMath.target,
      },
    });
    factory = await Factory.deploy();
    await factory.waitForDeployment();

    // Deploy LiquidationLogic
    const LiquidationLogic = await ethers.getContractFactory("LiquidationLogic");
    liquidationLogic = await LiquidationLogic.deploy(ethers.ZeroAddress, priceOracle.target);
    await liquidationLogic.waitForDeployment();

    // Create LendingPool via factory
    await factory.connect(deployer).createLendingPool(
      tokenA.target,
      tokenB.target,
      priceOracle.target,
      liquidationLogic.target
    );

    // Get LendingPool address from factory
    const lendingPoolAddr = await factory.getLendingPool(tokenA.target, tokenB.target);
    lendingPool = await ethers.getContractAt("LendingPool", lendingPoolAddr);

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

    // Distribute tokens
    await tokenA.transfer(user1.address, ethers.parseEther("10000")).then((tx) => tx.wait());
    await tokenB.transfer(user1.address, ethers.parseEther("10000")).then((tx) => tx.wait());
    await tokenA.transfer(lendingPoolAddr, ethers.parseEther("1000")).then((tx) => tx.wait());
    await tokenB.transfer(lendingPoolAddr, ethers.parseEther("1000")).then((tx) => tx.wait());
    await tokenA.transfer(pool.target, ethers.parseEther("1000")).then((tx) => tx.wait());
    await tokenB.transfer(pool.target, ethers.parseEther("1000")).then((tx) => tx.wait());

    // Approve router and lendingPool for user1
    await tokenA.connect(user1).approve(router.target, ethers.parseEther("10000"));
    await tokenB.connect(user1).approve(router.target, ethers.parseEther("10000"));
    await tokenA.connect(user1).approve(lendingPoolAddr, ethers.parseEther("10000"));
    await tokenB.connect(user1).approve(lendingPoolAddr, ethers.parseEther("10000"));

    // Verify initial balances
    expect(await tokenA.balanceOf(user1.address)).to.equal(ethers.parseEther("10000"));
    expect(await tokenB.balanceOf(user1.address)).to.equal(ethers.parseEther("10000"));
    expect(await tokenA.balanceOf(lendingPoolAddr)).to.equal(ethers.parseEther("1000"));
    expect(await tokenB.balanceOf(lendingPoolAddr)).to.equal(ethers.parseEther("1000"));
    expect(await tokenA.balanceOf(pool.target)).to.equal(ethers.parseEther("1000"));
    expect(await tokenB.balanceOf(pool.target)).to.equal(ethers.parseEther("1000"));
  });

  it("should deploy router with correct factory address", async function () {
    expect(await router.factory()).to.equal(factory.target);
  });

  it("should add liquidity to a pool", async function () {
    const amountA = ethers.parseEther("100");
    const amountB = ethers.parseEther("100");
    const initialBalance = await liquidityToken.balanceOf(user1.address);

    const tx = await router.connect(user1).addLiquidity(
      tokenA.target,
      tokenB.target,
      amountA,
      amountB,
      -887272,
      887272
    );
    await expect(tx)
      .to.emit(pool, "LiquidityAdded")
      .withArgs(user1.address, amountA, amountB, ethers.parseEther("100"));

    expect(await liquidityToken.balanceOf(user1.address)).to.equal(initialBalance + ethers.parseEther("100"));
    expect(await pool.liquidity(user1.address)).to.equal(ethers.parseEther("100"));
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
    const amountOut = ethers.parseEther("9.9"); // 1% fee: 10 * 0.99
    const initialBalanceB = await tokenB.balanceOf(user1.address);

    const tx = await router.connect(user1).swap(
      tokenA.target,
      tokenB.target,
      tokenA.target,
      amountIn,
      minAmountOut
    );
    await expect(tx)
      .to.emit(pool, "Swap")
      .withArgs(user1.address, tokenA.target, amountIn, amountOut);

    expect(await tokenB.balanceOf(user1.address)).to.equal(initialBalanceB + amountOut);
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
    const collateralAmount = ethers.parseEther("150");
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

    await router.connect(user1).addCollateral(tokenB.target, tokenA.target, additionalCollateral);

    expect(await lendingPool.collateral(user1.address)).to.equal(collateralAmount + additionalCollateral);
  });

  it("should withdraw collateral", async function () {
    const borrowAmount = ethers.parseEther("100");
    const collateralAmount = ethers.parseEther("200");
    const withdrawAmount = ethers.parseEther("25");
    await router.connect(user1).borrow(tokenA.target, borrowAmount, tokenB.target, collateralAmount);

    const initialBalanceB = await tokenB.balanceOf(user1.address);
    await router.connect(user1).withdrawCollateral(tokenB.target, tokenA.target, withdrawAmount);

    expect(await lendingPool.collateral(user1.address)).to.equal(collateralAmount - withdrawAmount);
    expect(await tokenB.balanceOf(user1.address)).to.equal(initialBalanceB + withdrawAmount);
  });

  it("should revert withdraw with insufficient collateral", async function () {
    const borrowAmount = ethers.parseEther("100");
    const collateralAmount = ethers.parseEther("150");
    await router.connect(user1).borrow(tokenA.target, borrowAmount, tokenB.target, collateralAmount);

    await expect(
      router.connect(user1).withdrawCollateral(tokenB.target, tokenA.target, ethers.parseEther("100"))
    ).to.be.revertedWith("Insufficient collateral after withdrawal");
  });
});