const fs = require('fs');
const path = require('path');

const contracts = [
  { name: 'ERC20', path: 'core/ERC20.sol' },
  { name: 'LiquidityToken', path: 'core/LiquidityToken.sol' },
  { name: 'PriceOracle', path: 'oracle/PriceOracle.sol' },
  { name: 'CoFinancePool', path: 'core/CoFinancePool.sol' },
  { name: 'LendingPool', path: 'lending/LendingPool.sol' },
  { name: 'LiquidationLogic', path: 'lending/LiquidationLogic.sol' }
];

let artifacts = {};

contracts.forEach(({ name, path: contractPath }) => {
  const artifactPath = path.join(__dirname, `../artifacts/contracts/${contractPath}/${name}.json`);
  const artifact = JSON.parse(fs.readFileSync(artifactPath));
  artifacts[name] = {
    abi: artifact.abi,
    bytecode: artifact.bytecode
  };
});

fs.writeFileSync(
  path.join(__dirname, 'artifacts.js'),
  `module.exports = ${JSON.stringify(artifacts, null, 2)};\n`
);

console.log('artifacts.js generated successfully!');