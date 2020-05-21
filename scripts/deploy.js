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

  let contracts = {};

  // Deploy DALP Token
  const DALPName = "DALP";
  const DALP = await ethers.getContractFactory(DALPName);
  const dalp = await DALP.deploy();

  await dalp.deployed();

  contracts[`${DALPName}Address`] = dalp.address;

  displayContractInfo(dalp, "DALP Token");

  // Deploy DALP Manager
  const DALPManagerName = "DALPManager";
  const DALPManager = await ethers.getContractFactory(DALPManagerName);
  const dalpManager = await DALPManager.deploy("0xf164fC0Ec4E93095b804a4795bBe1e041497b92a");

  await dalpManager.deployed();

  contracts[`${DALPManagerName}Address`] = dalpManager.address;

  await dalp.setManagerContractAddress(dalpManager.address);
  await dalpManager.setTokenContract(dalp.address);

  displayContractInfo(dalp, "DALP Manager");

  // Write contract addresses to a network config file
  fs.writeFileSync(`artifacts/${network.name}.json`, JSON.stringify(contracts, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
