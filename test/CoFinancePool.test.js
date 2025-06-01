const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CoFinancePool", function () {
  let deployer, user;
  let token0, token1, liquidityToken, priceOracle, pool, lendingPool, liquidationLogic;

  beforeEach(async function () {
    [deployer, user] = await ethers.getSigners();

    // Use the custom ERC20 contract from core/
    const ERC20 = await ethers.getContractFactory("core/ERC20");
    token0 = await ERC20.deploy("Token A", "TKA", ethers.utils.parseEther("1000000"));
    token1 = await ERC20.deploy("Token B", "TKB", ethers.utils.parseEther("1000000"));

    // Fix LiquidityToken deployment
    const LiquidityToken = await ethers.getContractFactory("core/LiquidityToken");
    liquidityToken = await LiquidityToken.deploy("Liquidity Token", "LPT");

    const PriceOracle = await ethers.getContractFactory("oracle/PriceOracle");
    priceOracle = await PriceOracle.deploy(await token0.getAddress(), 3600);

    const CoFinancePool = await ethers.getContractFactory("core/CoFinancePool");
    pool = await CoFinancePool.deploy(
      await token0.getAddress(),
      await token1.getAddress(),
      await liquidityToken.getAddress(),
      await priceOracle.getAddress()
    );

    await liquidityToken.setCoFinanceContract(await pool.getAddress());

    const LiquidationLogic = await ethers.getContractFactory("lending/LiquidationLogic");
    liquidationLogic = await LiquidationLogic.deploy(await pool.getAddress(), await priceOracle.getAddress());

    const LendingPool = await ethers.getContractFactory("lending/LendingPool");
    lendingPool = await LendingPool.deploy(
      await token0.getAddress(),
      await token1.getAddress(),
      await priceOracle.getAddress(),
      await liquidationLogic.getAddress()
    );
  });

  it("should add liquidity", async function () {
    await token0.approve(await pool.getAddress(), ethers.utils.parseEther("1000"));
    await token1.approve(await pool.getAddress(), ethers.utils.parseEther("1000"));
    await pool.addLiquidity(
      ethers.utils.parseEther("100"),
      ethers.utils.parseEther("100"),
      -887272,
      887272
    );
    const balance = await liquidityToken.balanceOf(deployer.address);
    expect(balance).to.be.gt(0);
  });

  it("should perform a swap", async function () {
    await token0.approve(await pool.getAddress(), ethers.utils.parseEther("1000"));
    await token1.approve(await pool.getAddress(), ethers.utils.parseEther("1000"));
    await pool.addLiquidity(
      ethers.utils.parseEther("100"),
      ethers.utils.parseEther("100"),
      -887272,
      887272
    );

    await token0.transfer(user.address, ethers.utils.parseEther("100"));
    await token0.connect(user).approve(await pool.getAddress(), ethers.utils.parseEther("10"));
    await pool.connect(user).swap(
      await token0.getAddress(),
      ethers.utils.parseEther("10"),
      ethers.utils.parseEther("9"),
      user.address
    );
    const token1Balance = await token1.balanceOf(user.address);
    expect(token1Balance).to.be.gt(0);
  });

  it("should borrow and liquidate", async function () {
    await token0.approve(await pool.getAddress(), ethers.utils.parseEther("1000"));
    await token1.approve(await pool.getAddress(), ethers.utils.parseEther("1000"));
    await pool.addLiquidity(
      ethers.utils.parseEther("100"),
      ethers.utils.parseEther("100"),
      -887272,
      887272
    );

    await token1.transfer(user.address, ethers.utils.parseEther("200"));
    await token1.connect(user).approve(await lendingPool.getAddress(), ethers.utils.parseEther("200"));
    await lendingPool.connect(user).borrow(
      await token0.getAddress(),
      ethers.utils.parseEther("100"),
      await token1.getAddress(),
      ethers.utils.parseEther("200")
    );
    const borrowed = await lendingPool.borrowed(user.address);
    expect(borrowed).to.equal(ethers.utils.parseEther("100"));

    await priceOracle.setPrice("7922816251426433759354395033");
    const isLiquidatable = await liquidationLogic.isLiquidatable(user.address);
    expect(isLiquidatable).to.be.true;
    await liquidationLogic.liquidate(user.address, deployer.address);
  });
});