const { ethers } = require("hardhat");

async function deployToNetwork(networkName, ccipRouterAddress, chainSelector) {
  console.log(`Deploying to ${networkName}...`);
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  // Deploy mock tokens (for testing, replace with real tokens on testnets)
  const Token = await ethers.getContractFactory("MockERC20");
  const tokenA = await Token.deploy("Token A", "TKNA", ethers.utils.parseEther("1000000"));
  const tokenB = await Token.deploy("Token B", "TKNB", ethers.utils.parseEther("1000000"));
  await tokenA.deployed();
  await tokenB.deployed();
  console.log(`Token A deployed to: ${tokenA.address}`);
  console.log(`Token B deployed to: ${tokenB.address}`);

  // Deploy mock WETH
  const WETH = await ethers.getContractFactory("MockWETH");
  const weth = await WETH.deploy();
  await weth.deployed();
  console.log(`WETH deployed to: ${weth.address}`);

  // Use real Chainlink price feeds (update for Amoy if needed)
  const priceFeedA = "0x694AA1769357215DE4FAC081bf1f309aDC325306"; // ETH/USD
  const priceFeedB = "0xB7A5bd0345EF1Cc5E66bf61BdeC17D2461fBd968"; // USDT/USD

  // Deploy LiquidationLogic
  const LiquidationLogic = await ethers.getContractFactory("LiquidationLogic");
  const liquidationLogic = await LiquidationLogic.deploy(ethers.constants.AddressZero, ccipRouterAddress);
  await liquidationLogic.deployed();
  console.log(`LiquidationLogic deployed to: ${liquidationLogic.address}`);

  // Deploy Router
  const Router = await ethers.getContractFactory("Router");
  const router = await Router.deploy(ccipRouterAddress);
  await router.deployed();
  console.log(`Router deployed to: ${router.address}`);

  // Create a pool
  const tx = await router.createPool(
    tokenA.address,
    tokenB.address,
    "Liquidity Token",
    "LP",
    priceFeedA,
    priceFeedB,
    liquidationLogic.address
  );
  const receipt = await tx.wait();
  const poolAddress = receipt.events.find((e) => e.event === "PoolCreated").args.pool;
  console.log(`Pool created at: ${poolAddress}`);

  // Create a WETH pool
  const wethTx = await router.createPool(
    weth.address,
    tokenB.address,
    "WETH-TKNB LP",
    "WETHLP",
    priceFeedA,
    priceFeedB,
    liquidationLogic.address
  );
  const wethReceipt = await wethTx.wait();
  const wethPoolAddress = wethReceipt.events.find((e) => e.event === "PoolCreated").args.pool;
  console.log(`WETH Pool created at: ${wethPoolAddress}`);

  return { router, poolAddress, wethPoolAddress, tokenA, tokenB, weth, chainSelector };
}

async function main() {
  // Deploy on Sepolia
  const sepoliaCCIPRouter = "0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59";
  const sepoliaChainSelector = "16015286601757825753";
  const sepoliaDeployment = await deployToNetwork("Sepolia", sepoliaCCIPRouter, sepoliaChainSelector);

  // Deploy on Polygon Amoy
  const amoyCCIPRouter = "0x9C32fCB86BF0f4a1A8921a9Fe46de3198bb884B2";
  const amoyChainSelector = "16281711391670634445";
  const amoyDeployment = await deployToNetwork("Amoy", amoyCCIPRouter, amoyChainSelector);

  // Configure CCIP destination contracts
  console.log("Configuring CCIP destinations...");
  await sepoliaDeployment.router.setDestinationContract(
    amoyDeployment.chainSelector,
    amoyDeployment.router.address
  );
  await amoyDeployment.router.setDestinationContract(
    sepoliaDeployment.chainSelector,
    sepoliaDeployment.router.address
  );
  console.log("CCIP destinations configured.");

  console.log("Deployment complete!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});