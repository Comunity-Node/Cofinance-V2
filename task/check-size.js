// tasks/check-size.js
task("check-size", "Prints contract bytecode sizes")
  .setAction(async () => {
    const { ethers } = require("hardhat");
    const factory = await ethers.getContractFactory("CoFinanceFactory");
    const bytecode = (await factory.getDeployTransaction()).data;
    console.log(`CoFinanceFactory bytecode size: ${bytecode.length / 2} bytes`);
  });

// Run task
