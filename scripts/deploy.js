const fs = require("fs");

function displayContractInfo(contract, contractName) {
  console.log(`
    ${contractName} deployed
    -------------------
    Address: ${contract.address}
    Transaction: ${contract.deployTransaction.hash}
    Gas Used: ${contract.deployTransaction.gasLimit}
  `);
}

async function main() {
  if (!Object.keys(config.networks).includes(network.name)) {
    throw new Error("Not using a supported network for deployment");
  }

  const DALPName = "DALP";
  const DALP = await ethers.getContractFactory(DALPName);
  const dalp = await DALP.deploy();

  await dalp.deployed();

  fs.writeFileSync(`artifacts/${DALPName}.address`, dalp.address);

  displayContractInfo(dalp, "DALP Token");

  const DALPManagerName = "DALPManager";
  const DALPManager = await ethers.getContractFactory(DALPManagerName);
  const dalpManager = await DALPManager.deploy("0xf164fC0Ec4E93095b804a4795bBe1e041497b92a");

  await dalpManager.deployed();

  fs.writeFileSync(`artifacts/${DALPManagerName}.address`, dalpManager.address);

  displayContractInfo(dalp, "DALP Manager");
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
