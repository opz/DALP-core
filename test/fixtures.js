const { Contract, utils } = require("ethers");
const { deployContract } = require("ethereum-waffle");

const UniswapV2Factory = require("@uniswap/v2-core/build/UniswapV2Factory.json");
const IUniswapV2Pair = require("@uniswap/v2-core/build/IUniswapV2Pair.json");

const ERC20 = require("@uniswap/v2-periphery/build/ERC20.json");
const WETH9 = require("@uniswap/v2-periphery/build/WETH9.json");
const UniswapV2Router01 = require("@uniswap/v2-periphery/build/UniswapV2Router01.json");

const DALP = require("../artifacts/DALP.json");
const OracleManager = require("../artifacts/OracleManager.json");
const DALPManager = require("../artifacts/TestDALPManager.json");

async function uniswapV2Fixture(provider, [wallet]) {
  // Deploy tokens
  const tokenA = await deployContract(wallet, ERC20, [utils.parseEther("1000")]);
  const tokenB = await deployContract(wallet, ERC20, [utils.parseEther("1000")]);
  const WETH = await deployContract(wallet, WETH9);

  // Deploy v2 factory
  const factory = await deployContract(wallet, UniswapV2Factory, [wallet.address]);

  // Deploy v2 router
  const router = await deployContract(wallet, UniswapV2Router01, [factory.address, WETH.address]);

  // Create token A and B pair
  await factory.createPair(tokenA.address, tokenB.address);
  const pairAddress = await factory.getPair(tokenA.address, tokenB.address);
  const pair = new Contract(
    pairAddress,
    JSON.stringify(IUniswapV2Pair.abi),
    provider
  ).connect(wallet);

  // Add liquidity to token A and B pair
  await tokenA.transfer(pair.address, utils.parseEther("1"));
  await tokenB.transfer(pair.address, utils.parseEther("4"));
  await pair.mint(wallet.address);

  const token0Address = await pair.token0();
  const token0 = tokenA.address === token0Address ? tokenA : tokenB
  const token1 = tokenA.address === token0Address ? tokenB : tokenA

  // Create ETH and token 0 pair
  await factory.createPair(WETH.address, token0.address);
  const pairAddressWETH0 = await factory.getPair(WETH.address, token0.address);
  const pairWETH0 = new Contract(
    pairAddressWETH0,
    JSON.stringify(IUniswapV2Pair.abi),
    provider
  ).connect(wallet);

  // Add liquidity to ETH and token 0 pair
  const WETHAmount0 = utils.parseEther("4");
  await WETH.deposit({ value: WETHAmount0 });
  await WETH.transfer(pairWETH0.address, WETHAmount0);
  await token0.transfer(pairWETH0.address, utils.parseEther("1"));
  await pairWETH0.mint(wallet.address);

  // Create ETH and token 1 pair
  await factory.createPair(WETH.address, token1.address);
  const pairAddressWETH1 = await factory.getPair(WETH.address, token1.address);
  const pairWETH1 = new Contract(
    pairAddressWETH1,
    JSON.stringify(IUniswapV2Pair.abi),
    provider
  ).connect(wallet);

  // Add liquidity to ETH and token 1 pair
  const WETHAmount1 = utils.parseEther("4");
  await WETH.deposit({ value: WETHAmount1 });
  await WETH.transfer(pairWETH1.address, WETHAmount1);
  await token1.transfer(pairWETH1.address, utils.parseEther("4"));
  await pairWETH1.mint(wallet.address);

  return { token0, token1, WETH, factory, router, pair, pairWETH0, pairWETH1 };
}

async function dalpManagerFixture(provider, [wallet]) {
  const fixture = await uniswapV2Fixture(provider, [wallet]);
  const dalp = await deployContract(wallet, DALP);
  const oracle = await deployContract(
    wallet,
    OracleManager,
    [fixture.factory.address, fixture.WETH.address]
  );
  const dalpManager = await deployContract(
    wallet,
    DALPManager,
    [fixture.router.address, oracle.address],
    { gasLimit: 9500000 } // Waffle default gas limit is too low
  );

  await dalp.setManagerContractAddress(dalpManager.address);
  await dalpManager.setTokenContract(dalp.address);

  return { ...fixture, dalp, dalpManager, oracle };
}

module.exports = {
  uniswapV2Fixture,
  dalpManagerFixture
};
