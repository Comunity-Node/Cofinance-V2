const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("LendingPool", function () {
  let deployer, user, liquidator;
  let token0, token1, priceOracle, lendingPool, liquidationLogic, liquidityToken, pool;

  beforeEach(async function () {
    [deployer, user, liquidator] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("core/ERC20");
    token0 = await ERC20.deploy("Token A", "TKA", ethers.utils.parseEther("1000000"));
    token1 = await ERC20.deploy("Token B", "TKB", ethers.utils.parseEther("1000000"));

    const CustomPriceOracle = await ethers.getContractFactory("oracle/CustomPriceOracle");
    priceOracle = await CustomPriceOracle.deploy(await token0.getAddress(), await token1.getAddress());

    const LiquidityToken = await ethers.getContractFactory("core/LiquidityToken");
    liquidityToken = await LiquidityToken.deploy("Liquidity Token", "LPT");

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

    await token0.transfer(await lendingPool.getAddress(), ethers.utils.parseEther("10000"));
    await token1.transfer(await lendingPool.getAddress(), ethers.utils.parseEther("10000"));

    // Fund users
    await token0.transfer(user.address, ethers.utils.parseEther("1000"));
    await token1.transfer(user.address, ethers.utils.parseEther("1000"));
    await token0.transfer(liquidator.address, ethers.utils.parseEther("1000"));
    await token1.transfer(liquidator.address, ethers.utils.parseEther("1000"));

    // Grant LIQUIDATOR_ROLE
    await liquidationLogic.updateLiquidatorRole(liquidator.address, true);
  });

  describe("Borrow", function () {
    it("should borrow successfully with sufficient collateral", async function () {
      await priceOracle.setPrices(ethers.utils.parseEther("2"), ethers.utils.parseEther("0.5")); // token0 = 2, token1 = 0.5
      await token1.connect(user).approve(await lendingPool.getAddress(), ethers.utils.parseEther("200"));
      await expect(
        lendingPool.connect(user).borrow(
          await token0.getAddress(),
          ethers.utils.parseEther("50"), // $100
          await token1.getAddress(),
          ethers.utils.parseEther("200") // $100, 150% = $150
        )
      )
        .to.emit(lendingPool, "Borrow")
        .withArgs(
          user.address,
          await token0.getAddress(),
          ethers.utils.parseEther("50"),
          await token1.getAddress(),
          ethers.utils.parseEther("200")
        );

      expect(await lendingPool.borrowed(user.address)).to.equal(ethers.utils.parseEther("50"));
      expect(await lendingPool.collateral(user.address)).to.equal(ethers.utils.parseEther("200"));
      expect(await lendingPool.borrowedToken(user.address)).to.equal(await token0.getAddress());
      expect(await lendingPool.collateralToken(user.address)).to.equal(await token1.getAddress());
    });

    it("should revert with insufficient collateral", async function () {
      await priceOracle.setPrices(ethers.utils.parseEther("2"), ethers.utils.parseEther("0.5"));
      await token1.connect(user).approve(await lendingPool.getAddress(), ethers.utils.parseEther("100"));
      await expect(
        lendingPool.connect(user).borrow(
          await token0.getAddress(),
          ethers.utils.parseEther("50"), // $100
          await token1.getAddress(),
          ethers.utils.parseEther("100") // $50, below 150%
        )
      ).to.be.revertedWith("Insufficient collateral");
    });

    it("should revert with invalid token", async function () {
      await token1.connect(user).approve(await lendingPool.getAddress(), ethers.utils.parseEther("200"));
      await expect(
        lendingPool.connect(user).borrow(
          user.address,
          ethers.utils.parseEther("50"),
          await token1.getAddress(),
          ethers.utils.parseEther("200")
        )
      ).to.be.revertedWith("Invalid token");
    });

    it("should revert with existing borrow", async function () {
      await priceOracle.setPrices(ethers.utils.parseEther("2"), ethers.utils.parseEther("0.5"));
      await token1.connect(user).approve(await lendingPool.getAddress(), ethers.utils.parseEther("200"));
      await lendingPool.connect(user).borrow(
        await token0.getAddress(),
        ethers.utils.parseEther("50"),
        await token1.getAddress(),
        ethers.utils.parseEther("200")
      );
      await expect(
        lendingPool.connect(user).borrow(
          await token0.getAddress(),
          ethers.utils.parseEther("10"),
          await token1.getAddress(),
          ethers.utils.parseEther("50")
        )
      ).to.be.revertedWith("Existing borrow");
    });
  });

  describe("Liquidation", function () {
    beforeEach(async function () {
      await priceOracle.setPrices(ethers.utils.parseEther("2"), ethers.utils.parseEther("0.5"));
      await token1.connect(user).approve(await lendingPool.getAddress(), ethers.utils.parseEther("200"));
      await lendingPool.connect(user).borrow(
        await token0.getAddress(),
        ethers.utils.parseEther("50"), // $100
        await token1.getAddress(),
        ethers.utils.parseEther("200") // $100
      );
    });

    it("should liquidate undercollateralized position", async function () {
      await priceOracle.setPrices(ethers.utils.parseEther("1"), ethers.utils.parseEther("0.5")); // collateral = $100, borrow = $50, <120%
      expect(await liquidationLogic.isLiquidatable(user.address)).to.be.true;

      await token0.connect(liquidator).approve(await lendingPool.getAddress(), ethers.utils.parseEther("50"));
      await expect(liquidationLogic.connect(liquidator).liquidate(user.address, liquidator.address))
        .to.emit(liquidationLogic, "Liquidation")
        .withArgs(
          user.address,
          liquidator.address,
          await token0.getAddress(),
          ethers.utils.parseEther("50"),
          await token1.getAddress(),
          ethers.utils.parseEther("105") // 50 * (1/0.5) * 1.05
        );

      expect(await lendingPool.borrowed(user.address)).to.equal(0);
      expect(await lendingPool.collateral(user.address)).to.equal(ethers.utils.parseEther("95"));
      expect(await token1.balanceOf(liquidator.address)).to.equal(ethers.utils.parseEther("1105"));
      expect(await token0.balanceOf(liquidator.address)).to.equal(ethers.utils.parseEther("950"));
    });

    it("should revert if not liquidatable", async function () {
      await priceOracle.setPrices(ethers.utils.parseEther("2"), ethers.utils.parseEther("0.5")); // collateral = $100, borrow = $100, >=120%
      expect(await liquidationLogic.isLiquidatable(user.address)).to.be.false;
      await token0.connect(liquidator).approve(await lendingPool.getAddress(), ethers.utils.parseEther("50"));
      await expect(
        liquidationLogic.connect(liquidator).liquidate(user.address, liquidator.address)
      ).to.be.revertedWith("Position not liquidatable");
    });

    it("should revert if called by non-liquidator", async function () {
      await priceOracle.setPrices(ethers.utils.parseEther("1"), ethers.utils.parseEther("0.5"));
      await expect(
        liquidationLogic.connect(user).liquidate(user.address, user.address)
      ).to.be.revertedWith("AccessControl: account");
    });
  });
});