const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Router", function () {
  let deployer, user, user2;
  let tokenA, tokenB, weth, priceFeedA, priceFeedB, ccipRouter, liquidationLogic, router, pool, wethPool;

  beforeEach(async function () {
    [deployer, user, user2] = await ethers.getSigners();

    // Deploy mock tokens
    const Token = await ethers.getContractFactory("MockERC20");
    tokenA = await Token.deploy("Token A", "TKNA", ethers.utils.parseEther("1000000"));
    tokenB = await Token.deploy("Token B", "TKNB", ethers.utils.parseEther("1000000"));
    await tokenA.deployed();
    await tokenB.deployed();

    // Deploy mock WETH
    const WETH = await ethers.getContractFactory("MockWETH");
    weth = await WETH.deploy();
    await weth.deployed();

    // Deploy mock price feeds
    const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
    priceFeedA = await MockV3Aggregator.deploy(8, ethers.utils.parseUnits("2000", 8)); // ETH/USD
    priceFeedB = await MockV3Aggregator.deploy(8, ethers.utils.parseUnits("1", 8)); // USDT/USD
    await priceFeedA.deployed();
    await priceFeedB.deployed();

    // Deploy mock CCIP router
    const MockCCIPRouter = await ethers.getContractFactory("MockCCIPRouter");
    ccipRouter = await MockCCIPRouter.deploy();
    await ccipRouter.deployed();

    // Deploy LiquidationLogic
    const LiquidationLogic = await ethers.getContractFactory("LiquidationLogic");
    liquidationLogic = await LiquidationLogic.deploy(ethers.constants.AddressZero, ccipRouter.address);
    await liquidationLogic.deployed();

    // Deploy Router
    const Router = await ethers.getContractFactory("Router");
    router = await Router.deploy(ccipRouter.address);
    await router.deployed();

    // Create a pool
    const tx = await router.createPool(
      tokenA.address,
      tokenB.address,
      "Liquidity Token",
      "LP",
      priceFeedA.address,
      priceFeedB.address,
      liquidationLogic.address
    );
    const receipt = await tx.wait();
    pool = receipt.events.find((e) => e.event === "PoolCreated").args.pool;

    // Create a WETH pool
    const wethTx = await router.createPool(
      weth.address,
      tokenB.address,
      "WETH-TKNB LP",
      "WETHLP",
      priceFeedA.address,
      priceFeedB.address,
      liquidationLogic.address
    );
    const wethReceipt = await wethTx.wait();
    wethPool = wethReceipt.events.find((e) => e.event === "PoolCreated").args.pool;

    // Transfer tokens to users
    await tokenA.transfer(user.address, ethers.utils.parseEther("1000"));
    await tokenB.transfer(user.address, ethers.utils.parseEther("1000"));
    await tokenA.transfer(user2.address, ethers.utils.parseEther("1000"));
    await tokenB.transfer(user2.address, ethers.utils.parseEther("1000"));

    // Approve tokens
    await tokenA.connect(user).approve(router.address, ethers.utils.parseEther("1000"));
    await tokenB.connect(user).approve(router.address, ethers.utils.parseEther("1000"));
    await tokenA.connect(user2).approve(router.address, ethers.utils.parseEther("1000"));
    await tokenB.connect(user2).approve(router.address, ethers.utils.parseEther("1000"));
    await tokenA.connect(user).approve(pool, ethers.utils.parseEther("1000"));
    await tokenB.connect(user).approve(pool, ethers.utils.parseEther("1000"));
  });

  it("should create a pool", async function () {
    expect(pool).to.not.equal(ethers.constants.AddressZero);
    expect(await router.getPool(tokenA.address, tokenB.address)).to.equal(pool);
    expect(await router.getAllPools()).to.have.lengthOf(2); // Including WETH pool
  });

  it("should add liquidity", async function () {
    const poolContract = await ethers.getContractAt("CoFinanceUnifiedPool", pool);
    await router.connect(user).addLiquiditySingleToken(
      pool,
      tokenA.address,
      tokenB.address,
      ethers.utils.parseEther("100"),
      -1000,
      1000,
      Math.floor(Date.now() / 1000) + 3600
    );
    expect(await poolContract.liquidity(user.address)).to.be.gt(0);
  });

  it("should perform a swap", async function () {
    await router.connect(user).addLiquiditySingleToken(
      pool,
      tokenA.address,
      tokenB.address,
      ethers.utils.parseEther("100"),
      -1000,
      1000,
      Math.floor(Date.now() / 1000) + 3600
    );

    const balanceBefore = await tokenB.balanceOf(user.address);
    await router.connect(user).swapExactInput(
      pool,
      tokenA.address,
      tokenB.address,
      ethers.utils.parseEther("10"),
      0,
      user.address,
      Math.floor(Date.now() / 1000) + 3600
    );
    const balanceAfter = await tokenB.balanceOf(user.address);
    expect(balanceAfter).to.be.gt(balanceBefore);
  });

  it("should perform a swap with native ETH", async function () {
    await weth.connect(user).deposit({ value: ethers.utils.parseEther("1") });
    await weth.connect(user).approve(wethPool, ethers.utils.parseEther("1"));
    await tokenB.connect(user).approve(wethPool, ethers.utils.parseEther("100"));
    await router.connect(user).addLiquiditySingleToken(
      wethPool,
      weth.address,
      tokenB.address,
      ethers.utils.parseEther("1"),
      -1000,
      1000,
      Math.floor(Date.now() / 1000) + 3600
    );

    const balanceBefore = await tokenB.balanceOf(user.address);
    await router.connect(user).swapExactInputWithNative(
      wethPool,
      tokenB.address,
      0,
      user.address,
      Math.floor(Date.now() / 1000) + 3600,
      { value: ethers.utils.parseEther("0.1") }
    );
    const balanceAfter = await tokenB.balanceOf(user.address);
    expect(balanceAfter).to.be.gt(balanceBefore);
  });

  it("should borrow tokens", async function () {
    await router.connect(user).addLiquiditySingleToken(
      pool,
      tokenA.address,
      tokenB.address,
      ethers.utils.parseEther("100"),
      -1000,
      1000,
      Math.floor(Date.now() / 1000) + 3600
    );

    await router.connect(user).borrow(
      pool,
      tokenA.address,
      ethers.utils.parseEther("10"),
      tokenB.address,
      ethers.utils.parseEther("50")
    );

    const poolContract = await ethers.getContractAt("CoFinanceUnifiedPool", pool);
    expect(await poolContract.borrowed(user.address)).to.equal(ethers.utils.parseEther("10"));
    expect(await poolContract.collateral(user.address)).to.equal(ethers.utils.parseEther("50"));
  });

  it("should repay a loan", async function () {
    await router.connect(user).addLiquiditySingleToken(
      pool,
      tokenA.address,
      tokenB.address,
      ethers.utils.parseEther("100"),
      -1000,
      1000,
      Math.floor(Date.now() / 1000) + 3600
    );

    await router.connect(user).borrow(
      pool,
      tokenA.address,
      ethers.utils.parseEther("10"),
      tokenB.address,
      ethers.utils.parseEther("50")
    );

    await tokenA.connect(user).approve(pool, ethers.utils.parseEther("11")); // Include interest
    await router.connect(user).repay(pool, ethers.utils.parseEther("10"));

    const poolContract = await ethers.getContractAt("CoFinanceUnifiedPool", pool);
    expect(await poolContract.borrowed(user.address)).to.equal(0);
  });

  it("should stake liquidity tokens", async function () {
    await router.connect(user).addLiquiditySingleToken(
      pool,
      tokenA.address,
      tokenB.address,
      ethers.utils.parseEther("100"),
      -1000,
      1000,
      Math.floor(Date.now() / 1000) + 3600
    );

    const poolContract = await ethers.getContractAt("CoFinanceUnifiedPool", pool);
    const liquidityToken = await ethers.getContractAt("LiquidityToken", await poolContract.liquidityToken());
    await liquidityToken.connect(user).approve(pool, ethers.utils.parseEther("10"));
    await router.connect(user).stake(pool, ethers.utils.parseEther("10"));
    expect(await poolContract.stakedBalance(user.address)).to.equal(ethers.utils.parseEther("10"));
  });

  it("should withdraw staked tokens", async function () {
    await router.connect(user).addLiquiditySingleToken(
      pool,
      tokenA.address,
      tokenB.address,
      ethers.utils.parseEther("100"),
      -1000,
      1000,
      Math.floor(Date.now() / 1000) + 3600
    );

    const poolContract = await ethers.getContractAt("CoFinanceUnifiedPool", pool);
    const liquidityToken = await ethers.getContractAt("LiquidityToken", await poolContract.liquidityToken());
    await liquidityToken.connect(user).approve(pool, ethers.utils.parseEther("10"));
    await router.connect(user).stake(pool, ethers.utils.parseEther("10"));

    await router.connect(user).withdrawStake(pool, ethers.utils.parseEther("10"));
    expect(await poolContract.stakedBalance(user.address)).to.equal(0);
  });

  it("should perform a cross-chain swap", async function () {
    // Set up destination contract
    await router.setDestinationContract(1234, router.address); // Mock chain selector

    // Add liquidity to pool
    await router.connect(user).addLiquiditySingleToken(
      pool,
      tokenA.address,
      tokenB.address,
      ethers.utils.parseEther("100"),
      -1000,
      1000,
      Math.floor(Date.now() / 1000) + 3600
    );

    // Perform cross-chain swap
    const balanceBefore = await tokenB.balanceOf(user.address);
    await router.connect(user).swapExactInputCrossChain(
      tokenA.address,
      ethers.utils.parseEther("10"),
      1234,
      user.address,
      Math.floor(Date.now() / 1000) + 3600,
      { value: ethers.utils.parseEther("0.01") }
    );

    // Simulate CCIP message receipt
    const message = {
      messageId: ethers.utils.formatBytes32String("test"),
      sourceChainSelector: 1234,
      sender: ethers.utils.hexZeroPad(router.address, 32),
      data: router.interface.encodeFunctionData("executeCrossChainSwap", [
        user.address,
        tokenA.address,
        ethers.utils.parseEther("10"),
        user.address,
      ]),
      destTokenAmounts: [],
    };
    await ccipRouter.simulateReceive(router.address, message);

    const balanceAfter = await tokenB.balanceOf(user.address);
    expect(balanceAfter).to.be.gt(balanceBefore);
  });

  it("should perform a cross-chain loan", async function () {
    // Set up destination contract
    await router.setDestinationContract(1234, router.address);

    // Add liquidity to pool
    await router.connect(user).addLiquiditySingleToken(
      pool,
      tokenA.address,
      tokenB.address,
      ethers.utils.parseEther("100"),
      -1000,
      1000,
      Math.floor(Date.now() / 1000) + 3600
    );

    // Request cross-chain loan
    await router.connect(user).requestCrossChainLoan(
      tokenB.address,
      ethers.utils.parseEther("50"),
      1234,
      tokenA.address,
      ethers.utils.parseEther("10"),
      { value: ethers.utils.parseEther("0.01") }
    );

    // Simulate CCIP message receipt
    const message = {
      messageId: ethers.utils.formatBytes32String("test-loan"),
      sourceChainSelector: 1234,
      sender: ethers.utils.hexZeroPad(router.address, 32),
      data: router.interface.encodeFunctionData("executeCrossChainLoan", [
        user.address,
        tokenB.address,
        ethers.utils.parseEther("50"),
        tokenA.address,
        ethers.utils.parseEther("10"),
      ]),
      destTokenAmounts: [],
    };
    await ccipRouter.simulateReceive(router.address, message);

    const poolContract = await ethers.getContractAt("CoFinanceUnifiedPool", pool);
    expect(await poolContract.borrowed(user.address)).to.equal(ethers.utils.parseEther("10"));
    expect(await poolContract.collateral(user.address)).to.equal(ethers.utils.parseEther("50"));
  });
});