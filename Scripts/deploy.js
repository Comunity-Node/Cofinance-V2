const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying from account:", deployer.address);

  // Deploy ERC20 tokens
  const ERC20 = await hre.ethers.getContractFactory("ERC20");
  const token0 = await ERC20.deploy("Token A", "TKA", hre.ethers.utils.parseEther("1000000"));
  await token0.waitForDeployment();
  console.log("Token0 deployed at:", await token0.getAddress());

  const token1 = await ERC20.deploy("Token B", "TKB", hre.ethers.utils.parseEther("1000000"));
  await token1.waitForDeployment();
  console.log("Token1 deployed at:", await token1.getAddress());

  // Deploy LiquidityToken
  const LiquidityToken = await hre.ethers.getContractFactory("LiquidityToken");
  const liquidityToken = await LiquidityToken.deploy("Liquidity Token", "LPT");
  await liquidityToken.waitForDeployment();
  console.log("LiquidityToken deployed at:", await liquidityToken.getAddress());

  // Deploy PriceOracle
  const PriceOracle = await hre.ethers.getContractFactory("PriceOracle");
  const priceOracle = await PriceOracle.deploy(await token0.getAddress(), 3600);
  await priceOracle.waitForDeployment();
  console.log("PriceOracle deployed at:", await priceOracle.getAddress());

  // Deploy CoFinancePool
  const CoFinancePool = await hre.ethers.getContractFactory("CoFinancePool");
  const pool = await CoFinancePool.deploy(
    await token0.getAddress(),
    await token1.getAddress(),
    await liquidityToken.getAddress(),
    await priceOracle.getAddress()
  );
  await pool.waitForDeployment();
  console.log("CoFinancePool deployed at:", await pool.getAddress());

  // Configure LiquidityToken
  await liquidityToken.setCoFinanceContract(await pool.getAddress());
  console.log("LiquidityToken configured with CoFinancePool");

  // Deploy LiquidationLogic
  const LiquidationLogic = await hre.ethers.getContractFactory("LiquidationLogic");
  const liquidationLogic = await LiquidationLogic.deploy(await pool.getAddress(), await priceOracle.getAddress());
  await liquidationLogic.waitForDeployment();
  console.log("LiquidationLogic deployed at:", await liquidationLogic.getAddress());

  // Deploy LendingPool
  const LendingPool = await hre.ethers.getContractFactory("LendingPool");
  const lendingPool = await LendingPool.deploy(
    await token0.getAddress(),
    await token1.getAddress(),
    await priceOracle.getAddress(),
    await liquidationLogic.getAddress()
  );
  await lendingPool.waitForDeployment();
  console.log("LendingPool deployed at:", await lendingPool.getAddress());

  console.log("Deployment completed successfully!");
}

main().catch((error) => {
  console.error("Deployment failed:", error);
  process.exitCode = 1;
});