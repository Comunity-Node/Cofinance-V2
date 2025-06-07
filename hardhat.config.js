require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 800
      }
    }
  },
  networks: {
    hardhat: {}, // Local Hardhat network
  },
  paths: {
    artifacts: "./artifacts",
    sources: "./contracts"
  }
};