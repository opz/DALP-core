const fs = require("fs");
const { uniswapTokenPairs } = require(`../config/${network.name}.json`);

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

  const OracleName = "OracleManager";
  const OracleManager = await ethers.getContractFactory(OracleName);
  const oracleManager = await OracleManager.deploy(
    "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f",
    "0xd0A1E359811322d97991E03f863a0C30C2cF029C"
  );

  await oracleManager.deployed();
  contracts[`${OracleName}Address`] = oracleManager.address;

  displayContractInfo(oracleManager, "Oracle Manager");

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
  const dalpManager = await DALPManager.deploy(
    "0xf164fC0Ec4E93095b804a4795bBe1e041497b92a",
    oracleManager.address,
    uniswapTokenPairs
  );

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
