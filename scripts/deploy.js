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
  const DALP = await ethers.getContractFactory("DALP");
  const dalp = await DALP.deploy();

  await dalp.deployed();

  displayContractInfo(dalp, "DALP Token");

  const DALPManager = await ethers.getContractFactory("DALPManager");
  const dalpManager = await DALPManager.deploy("0xf164fC0Ec4E93095b804a4795bBe1e041497b92a");

  await dalpManager.deployed();

  displayContractInfo(dalp, "DALP Manager");
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
