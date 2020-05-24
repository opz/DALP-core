const { DALPManagerAddress } = require(`../artifacts/${network.name}.json`);

async function main() {
  console.log("Reallocating liquidity...");
  const dalpManager = await ethers.getContractAt("DALPManager", DALPManagerAddress);
  await dalpManager.reallocateLiquidity();

  const { 0: token0, 1: token1 } = await dalpManager.getActiveUniswapV2Tokens();
  console.log(`New active tokens are ${token0} and ${token1}`);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });

