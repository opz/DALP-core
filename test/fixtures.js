const { Contract, utils } = require("ethers");
const { deployContract } = require("ethereum-waffle");

const UniswapV2Factory = require("@uniswap/v2-core/build/UniswapV2Factory.json");
const IUniswapV2Pair = require("@uniswap/v2-core/build/IUniswapV2Pair.json");

const ERC20 = require("@uniswap/v2-periphery/build/ERC20.json");
const WETH9 = require("@uniswap/v2-periphery/build/WETH9.json");
const UniswapV2Router01 = require("@uniswap/v2-periphery/build/UniswapV2Router01.json");

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

  // Create ETH and token A pair
  await factory.createPair(WETH.address, tokenA.address);
  const pairAddressWETHA = await factory.getPair(WETH.address, tokenA.address);
  const pairWETHA = new Contract(
    pairAddressWETHA,
    JSON.stringify(IUniswapV2Pair.abi),
    provider
  ).connect(wallet);

  // Add liquidity to ETH and token A pair
  const WETHAmountA = utils.parseEther("4");
  await WETH.deposit({ value: WETHAmountA });
  await WETH.transfer(pairWETHA.address, WETHAmountA);
  await tokenA.transfer(pairWETHA.address, utils.parseEther("1"));
  await pairWETHA.mint(wallet.address);

  // Create ETH and token B pair
  await factory.createPair(WETH.address, tokenB.address);
  const pairAddressWETHB = await factory.getPair(WETH.address, tokenB.address);
  const pairWETHB = new Contract(
    pairAddressWETHB,
    JSON.stringify(IUniswapV2Pair.abi),
    provider
  ).connect(wallet);

  // Add liquidity to ETH and token B pair
  const WETHAmountB = utils.parseEther("4");
  await WETH.deposit({ value: WETHAmountB });
  await WETH.transfer(pairWETHB.address, WETHAmountB);
  await tokenB.transfer(pairWETHB.address, utils.parseEther("4"));
  await pairWETHB.mint(wallet.address);

  return { token0, token1, WETH, factory, router, pair, pairWETHA, pairWETHB };
}

module.exports = {
  uniswapV2Fixture
};
