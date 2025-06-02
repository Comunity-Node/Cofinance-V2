const fs = require('fs');
const path = require('path');

const contracts = [
  { name: 'GovernanceToken', path: 'core/GovernanceToken.sol' },
  { name: 'LiquidityToken', path: 'core/LiquidityToken.sol' },
  { name: 'PriceOracle', path: 'oracle/PriceOracle.sol' },
  { name: 'CustomPriceOracle', path: 'oracle/CustomPriceOracle.sol' }, 
  { name: 'CoFinancePool', path: 'core/CoFinancePool.sol' },
  { name: 'LendingPool', path: 'lending/LendingPool.sol' },
  { name: 'LiquidationLogic', path: 'lending/LiquidationLogic.sol' },
  { name: 'Launchpad', path: 'launchpad/Launchpad.sol' },
  { name: 'CoFinanceFactory', path: 'core/CoFinanceFactory.sol' },
  { name: 'ERC20', path: 'core/ERC20.sol' },
];

let artifacts = {};

contracts.forEach(({ name, path: contractPath }) => {
  const artifactPath = path.join(__dirname, `../artifacts/contracts/${contractPath}/${name}.json`);
  try {
    if (fs.existsSync(artifactPath)) {
      const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));
      artifacts[name] = {
        abi: artifact.abi,
        bytecode: artifact.bytecode,
      };
    } else {
      console.warn(`Artifact not found for ${name} at ${artifactPath}. Ensure contract is compiled.`);
    }
  } catch (error) {
    console.error(`Failed to load artifact for ${name}:`, error.message);
  }
});

const outputPath = path.join(__dirname, 'artifacts.js');
fs.writeFileSync(outputPath, `module.exports = ${JSON.stringify(artifacts, null, 2)};\n`);

console.log(`artifacts.js generated successfully at ${outputPath}!`);
