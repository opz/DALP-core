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
  if (!Object.keys(config.networks).includes(network)) {
    throw new Error("Not using a supported network for deployment");
  }

  const OracleManager = await ethers.getContractFactory("OracleManager");
  const oracleManager = await OracleManager.deploy();

  await oracleManager.deployed();

  displayContractInfo(oracleManager, "Oracle Manager");

  const DALP = await ethers.getContractFactory("DALP");
  const dalp = await DALP.deploy();

  await dalp.deployed();

  displayContractInfo(dalp, "DALP Token");

  const DALPManager = await ethers.getContractFactory("DALPManager");
  const dalpManager = await DALPManager.deploy(
    "0xf164fC0Ec4E93095b804a4795bBe1e041497b92a",
    oracleManager.address
  );

  await dalpManager.deployed();

  displayContractInfo(dalp, "DALP Manager");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
