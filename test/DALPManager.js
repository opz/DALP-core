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
  let dalp;
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
      dalp,
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
    const period = Number(await oracle.PERIOD());
    const in2Hours = Math.floor(Date.now() / 1000) + period + 600;
    await router.swapExactETHForTokens(
      0,
      [WETH.address, token0.address],
      wallet.address,
      in2Hours,
      { value: utils.parseEther("1") }
    );
    await provider.send("evm_mine", [in2Hours]);
    await oracle.update(token0.address);
    const pairRating = await dalpManager.getUniswapV2PairRating(pairWETH0.address);

    const rating = utils.bigNumberify("100077198575464220");
    expect(pairRating).to.be.above(rating.sub(rating.div(20)));
    expect(pairRating).to.be.below(rating.add(rating.div(20)));
  });

  it("_findBestUpdatedUniswapV2Pair", async () => {
    const period = Number(await oracle.PERIOD());
    const in2Hours = Math.floor(Date.now() / 1000) + period + 600;

    // Create growth for token0 <-> WETH pair
    await router.swapExactETHForTokens(
      0,
      [WETH.address, token0.address],
      wallet.address,
      in2Hours,
      { value: utils.parseEther("1") }
    );

    // Reduce total value of liquidity by removing liquidity
    const withdraw = (await pairWETH0.balanceOf(wallet.address)).div(2);
    await pairWETH0.approve(router.address, withdraw);
    await router.removeLiquidity(WETH.address, token0.address, withdraw, 0, 0, wallet.address, in2Hours);

    // Advance time so oracle will update the average price
    await provider.send("evm_mine", [in2Hours]);

    // token0 <-> WETH pair should be best because it has the most growth with least liquidity
    expect(dalpManager.testFindBestUpdatedUniswapV2Pair(pairWETH0.address)).to.not.reverted;
  });

  it("reallocateLiquidity", async () => {
    const period = Number(await oracle.PERIOD());
    const in2Hours = Math.floor(Date.now() / 1000) + period + 600;

    // Create growth for token0 <-> WETH pair
    await router.swapExactETHForTokens(
      0,
      [WETH.address, token0.address],
      wallet.address,
      in2Hours,
      { value: utils.parseEther("1") }
    );

    // Reduce total value of liquidity by removing liquidity
    const withdraw = (await pairWETH0.balanceOf(wallet.address)).div(2);
    await pairWETH0.approve(router.address, withdraw);
    await router.removeLiquidity(WETH.address, token0.address, withdraw, 0, 0, wallet.address, in2Hours);

    // Advance time so oracle will update the average price
    await provider.send("evm_mine", [in2Hours]);

    // Send ETH for the DALP to invest with
    const tx = { to: dalpManager.address, value: utils.parseEther("1") };
    await wallet.sendTransaction(tx);

    await dalpManager.reallocateLiquidity();

    // DALPManager should now have LP shares in the token0 <-> WETH pair
    expect(await pairWETH0.balanceOf(dalpManager.address)).to.be.gt(0);
  });

  it("calculateMintAmount", async () => {
    const period = Number(await oracle.PERIOD());
    const in2Hours = Math.floor(Date.now() / 1000) + period + 600;

    const amountFromNothing = await dalpManager.calculateMintAmount(utils.parseEther("1"));
    expect(amountFromNothing).to.be.gt(0);

    await dalpManager.mint({ value: utils.parseEther("1") });

    const amountAfterMint = await dalpManager.calculateMintAmount(utils.parseEther("1"));
    expect(amountFromNothing).to.be.gt(0);

    // advance time so oracle will update the average price
    await provider.send("evm_mine", [in2Hours]);

    await dalpManager.reallocateLiquidity();

    const amountAfterInvest = await dalpManager.calculateMintAmount(utils.parseEther("1"));
    expect(amountAfterInvest).to.be.gt(0);
  });

  it("mint", async () => {
    const period = Number(await oracle.PERIOD());
    const in2Hours = Math.floor(Date.now() / 1000) + period + 600;

    await dalpManager.mint({ value: utils.parseEther("1") });
    const balance1 = await dalp.balanceOf(wallet.address);
    expect(balance1).to.be.gt(0);

    await dalpManager.mint({ value: utils.parseEther("1") });
    const balance2 = await dalp.balanceOf(wallet.address);
    expect(balance2).to.be.gt(balance1);

    // Create growth for token0 <-> WETH pair
    await router.swapExactETHForTokens(
      0,
      [WETH.address, token0.address],
      wallet.address,
      in2Hours,
      { value: utils.parseEther("1") }
    );

    // Reduce total value of liquidity by removing liquidity
    const withdraw = (await pairWETH0.balanceOf(wallet.address)).div(2);
    await pairWETH0.approve(router.address, withdraw);
    await router.removeLiquidity(WETH.address, token0.address, withdraw, 0, 0, wallet.address, in2Hours);

    // advance time so oracle will update the average price
    await provider.send("evm_mine", [in2Hours]);

    await dalpManager.reallocateLiquidity();
    const lpShareBalance = await pairWETH0.balanceOf(dalpManager.address);
    expect(lpShareBalance).to.be.gt(0);

    await dalpManager.mint({ value: utils.parseEther("1") });
    const balanceWithActiveInvestment = await dalp.balanceOf(wallet.address);
    expect(balanceWithActiveInvestment).to.be.gt(balance2);

    // Check that the new ETH sent to the mint function has been invested by the DALP
    const newLPShareBalance = await pairWETH0.balanceOf(dalpManager.address);
    expect(newLPShareBalance).to.be.gt(lpShareBalance);
  });
});
