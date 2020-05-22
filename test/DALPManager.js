const { expect } = require("chai");
const { utils } = require("ethers");
const { solidity, createFixtureLoader } = require("ethereum-waffle");

const { dalpManagerFixture } = require("./fixtures.js");

describe("DALPManager", () => {
  const provider = waffle.provider
  const [wallet] = provider.getWallets();
  const loadFixture = createFixtureLoader(provider, [wallet]);

  let token0;
  let token1;
  let WETH
  let router;
  let pair;
  let pairWETH0;
  let pairWETH1;
  let dalpManager;
  let oracle;

  beforeEach(async () => {
    ({
      token0,
      token1,
      WETH,
      router,
      pair,
      pairWETH0,
      pairWETH1,
      dalpManager,
      oracle
    } = await loadFixture(dalpManagerFixture));
  });

  it("_addUniswapV2Liquidity", async () => {
    // Test adding liquidity to token <-> token pair
    const tx1 = { to: dalpManager.address, value: utils.parseEther("1") };
    await wallet.sendTransaction(tx1);
    await dalpManager.addUniswapV2Liquidity(token0.address, token1.address);
    expect(await pair.balanceOf(dalpManager.address)).to.be.gt(0);

    // Test adding liquidity to token <-> WETH pair
    const tx2 = { to: dalpManager.address, value: utils.parseEther("1") };
    await wallet.sendTransaction(tx2);
    await dalpManager.addUniswapV2Liquidity(token0.address, WETH.address);
    expect(await pairWETH0.balanceOf(dalpManager.address)).to.be.gt(0);
  });

  it("_getUniswapV2PairRating", async () => {
    await router.swapExactETHForTokens(
      0,
      [WETH.address, token0.address],
      wallet.address,
      Date.now() + 100000,
      { value: utils.parseEther("1") }
    );
    await oracle.update(token0.address);
    await oracle.update(token1.address);
    const pairRating = await dalpManager.getUniswapV2PairRating(pair.address);
    expect(pairRating).to.be.equal("122142066491087372");
  });
});
