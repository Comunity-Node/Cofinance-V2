const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CoFinancePool", function () {
  let deployer, user1, user2;
  let token0, token1, liquidityToken, priceOracle, pool;

  beforeEach(async function () {
    [deployer, user1, user2] = await ethers.getSigners();

    console.log("Deploying tokens...");
    const ERC20 = await ethers.getContractFactory("GovernanceToken");
    token0 = await ERC20.deploy("Token A", "TKA", ethers.utils.parseEther("1000000"));
    await token0.waitForDeployment();
    token1 = await ERC20.deploy("Token B", "TKB", ethers.utils.parseEther("1000000"));
    await token1.waitForDeployment();

    console.log("Deploying liquidity token...");
    const LiquidityToken = await ethers.getContractFactory("LiquidityToken");
    liquidityToken = await LiquidityToken.waitForDeployment("Liquidity Token", "LPT");
    await liquidityToken.waitForDeployment();

    console.log("Deploying price oracle...");
    const CustomPriceOracle = await ethers.getContractFactory("CustomPriceOracle");
    priceOracle = await CustomPriceOracle.wait(token0.target, token1.target);
    await priceOracle.waitForDeployment();

    console.log("Deploying CoFinancePool contract...");
    const CoFinancePool = await ethers.getContractFactory("CoFinancePool");
    pool = await CoFinancePool.deploy(
      token0.address,
      token1.address,
      liquidityToken.address,
      priceOracle.address
    );
    await pool.waitForDeployment();

    console.log("Setting pool as CoFinance contract in liquidity token...");
    await liquidityToken.setCoFinanceContract(pool.address);

    // Fund users
    console.log("Funding user1 and user2 with tokens...");
    await token0.transfer(user1.address, ethers.utils.parseEther("10000"));
    await token1.transfer(user1.address, ethers.utils.parseEther("10000"));
    await token0.transfer(user2.address, ethers.utils.parseEther("10000"));
    await token1.transfer(user2.address, ethers.utils.parseEther("10000"));
  });

  describe("Pool Creation", function () {
    it("should initialize pool correctly", async function () {
      console.log("Checking pool initialization...");
      expect(await pool.token0()).to.equal(await token0.getAddress());
      expect(await pool.token1()).to.equal(await token1.getAddress());
      expect(await pool.liquidityToken()).to.equal(await liquidityToken.getAddress());
      expect(await pool.priceOracle()).to.equal(await priceOracle.getAddress());
      expect(await pool.hasRole(await pool.DEFAULT_ADMIN_ROLE(), deployer.address)).to.be.true;
    });

    it("should revert with invalid token addresses", async function () {
      console.log("Testing invalid token address deployment...");
      const CoFinancePool = await ethers.getContractFactory("CoFinancePool");
      await expect(
        CoFinancePool.deploy(
          ethers.constants.AddressZero,
          await token1.getAddress(),
          await liquidityToken.getAddress(),
          await priceOracle.getAddress()
        )
      ).to.be.reverted;
    });
  });

  describe("Add Liquidity", function () {
    it("should add liquidity successfully", async function () {
      console.log("Approving tokens for user1...");
      await token0.connect(user1).approve(await pool.getAddress(), ethers.utils.parseEther("100"));
      await token1.connect(user1).approve(await pool.getAddress(), ethers.utils.parseEther("100"));
      console.log("Tokens approved, adding liquidity...");

      const tx = await pool.connect(user1).addLiquidity(
        ethers.utils.parseEther("100"),
        ethers.utils.parseEther("100"),
        -887272,
        887272
      );
      console.log("Liquidity added tx hash:", tx.hash);
      await tx.wait();

      const balance = await liquidityToken.balanceOf(user1.address);
      console.log("Liquidity token balance for user1:", ethers.utils.formatEther(balance));

      await expect(tx)
        .to.emit(pool, "LiquidityAdded")
        .withArgs(user1.address, ethers.utils.parseEther("100"), ethers.utils.parseEther("100"), ethers.utils.parseEther("200"));

      expect(balance).to.equal(ethers.utils.parseEther("200"));
      expect(await pool.liquidity(user1.address)).to.equal(ethers.utils.parseEther("200"));
    });

    it("should revert with zero amounts", async function () {
      console.log("Testing addLiquidity revert with zero amounts...");
      await expect(
        pool.connect(user1).addLiquidity(0, ethers.utils.parseEther("100"), -887272, 887272)
      ).to.be.revertedWith("Invalid amounts");
    });

    it("should revert with invalid ticks", async function () {
      console.log("Approving tokens for user1 for invalid ticks test...");
      await token0.connect(user1).approve(await pool.getAddress(), ethers.utils.parseEther("100"));
      await token1.connect(user1).approve(await pool.getAddress(), ethers.utils.parseEther("100"));
      console.log("Testing addLiquidity revert with invalid ticks...");
      await expect(
        pool.connect(user1).addLiquidity(
          ethers.utils.parseEther("100"),
          ethers.utils.parseEther("100"),
          887272,
          -887272
        )
      ).to.be.revertedWith("Invalid ticks");
    });
  });

  describe("Swap", function () {
    beforeEach(async function () {
      console.log("Approving tokens and adding liquidity for swap tests...");
      await token0.connect(user1).approve(await pool.getAddress(), ethers.utils.parseEther("1000"));
      await token1.connect(user1).approve(await pool.getAddress(), ethers.utils.parseEther("1000"));
      await pool.connect(user1).addLiquidity(
        ethers.utils.parseEther("1000"),
        ethers.utils.parseEther("1000"),
        -887272,
        887272
      );
      await priceOracle.setPrices(ethers.utils.parseEther("2"), ethers.utils.parseEther("0.5")); // token0 = 2, token1 = 0.5
      console.log("Liquidity added and prices set for swap tests.");
    });

    it("should swap token0 for token1", async function () {
      console.log("User2 approving token0 for swap...");
      await token0.connect(user2).approve(await pool.getAddress(), ethers.utils.parseEther("10"));
      const amountOutMin = ethers.utils.parseEther("19"); // 10 * 2 * 0.99 = 19.8

      const tx = await pool.connect(user2).swap(
        await token0.getAddress(),
        ethers.utils.parseEther("10"),
        amountOutMin,
        user2.address
      );
      console.log("Swap tx hash (token0 -> token1):", tx.hash);
      await tx.wait();

      await expect(tx)
        .to.emit(pool, "Swap")
        .withArgs(user2.address, await token0.getAddress(), ethers.utils.parseEther("10"), ethers.utils.parseEther("19.8"));

      const balanceToken1 = await token1.balanceOf(user2.address);
      console.log("User2 token1 balance after swap:", ethers.utils.formatEther(balanceToken1));

      expect(balanceToken1).to.equal(ethers.utils.parseEther("10019.8"));
    });

    it("should swap token1 for token0", async function () {
      console.log("User2 approving token1 for swap...");
      await token1.connect(user2).approve(await pool.getAddress(), ethers.utils.parseEther("40"));
      const amountOutMin = ethers.utils.parseEther("4.95"); // 40 * 0.5 / 2 * 0.99 = 4.95

      const tx = await pool.connect(user2).swap(
        await token1.getAddress(),
        ethers.utils.parseEther("40"),
        amountOutMin,
        user2.address
      );
      console.log("Swap tx hash (token1 -> token0):", tx.hash);
      await tx.wait();

      await expect(tx)
        .to.emit(pool, "Swap")
        .withArgs(user2.address, await token1.getAddress(), ethers.utils.parseEther("40"), ethers.utils.parseEther("4.95"));

      const balanceToken0 = await token0.balanceOf(user2.address);
      console.log("User2 token0 balance after swap:", ethers.utils.formatEther(balanceToken0));

      expect(balanceToken0).to.equal(ethers.utils.parseEther("10004.95"));
    });

    it("should revert with insufficient output amount", async function () {
      console.log("User2 approving token0 for swap with insufficient output test...");
      await token0.connect(user2).approve(await pool.getAddress(), ethers.utils.parseEther("10"));
      await expect(
        pool.connect(user2).swap(
          await token0.getAddress(),
          ethers.utils.parseEther("10"),
          ethers.utils.parseEther("20"), // Too high
          user2.address
        )
      ).to.be.revertedWith("Insufficient output");
    });

    it("should revert with invalid token", async function () {
      console.log("Testing swap revert with invalid token...");
      await expect(
        pool.connect(user2).swap(
          user2.address, // invalid token address
          ethers.utils.parseEther("10"),
          ethers.utils.parseEther("5"),
          user2.address
        )
      ).to.be.revertedWith("Invalid token");
    });
  });
});
