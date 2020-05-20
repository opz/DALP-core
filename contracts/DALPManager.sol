pragma solidity ^0.6.6;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {FixedPoint} from "@uniswap/lib/contracts/libraries/FixedPoint.sol";
import {UniswapV2Library} from "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";
import {IUniswapV2Router01} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";

import {DALP} from "./DALP.sol";
import {OracleManager} from "./OracleManager.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

contract DALPManager is Ownable {
    //----------------------------------------
    // Type definitions
    //----------------------------------------

    using SafeMath for uint256;
    using FixedPoint for *;
    using SafeERC20 for IERC20;
    // using SafeMath for uint256;

    //----------------------------------------
    // State variables
    //----------------------------------------

    uint112 private constant MAX_UINT112 = uint112(-1);
    uint private constant UNISWAP_V2_DEADLINE_DELTA = 15 minutes;

    // Limit slippage to 0.5%
    uint112 private constant UNISWAP_V2_SLIPPAGE_LIMIT = 200;

    // token DALP is currently provisioning liquidity for
    // the WETH<=>activeTokenPair is current Uniswap pair
    // ex: DAI address
    address private activeTokenPair;

    // address of uniswap pair pool
    address private uniswapPair;

    // uniswap factory
    address factory;

    //----------------------------------------
    // State variables
    //----------------------------------------

    DALP public dalp; // DALP token
    IUniswapV2Router01 private immutable uniswapRouter;
    address private immutable WETH;
    OracleManager private oracle;

    //----------------------------------------
    // Events
    //----------------------------------------

    event AddUniswapLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountA,
        uint amountB,
        uint liquidity
    );

    //----------------------------------------
    // Constructor
    //----------------------------------------

    constructor(IUniswapV2Router01 _uniswapRouter, OracleManager _oracle, address _factory) public {
        uniswapRouter = _uniswapRouter;
        WETH = _uniswapRouter.WETH();
        oracle = _oracle;
        factory = _factory;
    }

    //----------------------------------------
    // Public functions
    //----------------------------------------

    // called by admin on deployment
    function setTokenContract(address _tokenAddress) public onlyOwner {
        dalp = DALP(_tokenAddress);
    }

    function mint() public payable {
        require(msg.value > 0, "Must send ETH");
        uint mintAmount = _calculateMintAmount(msg.value);
        dalp.mint(msg.sender, mintAmount);
    }

    function burn(uint tokensToBurn) public {
        require(tokensToBurn > 0, "Must burn tokens");
        require(dalp.balanceOf(msg.sender) >= tokensToBurn, "Insufficient balance");

        dalp.burn(msg.sender, tokensToBurn);
    }

    //----------------------------------------
    // Public views
    //----------------------------------------

    function getUniswapPoolTokenHoldings() public view returns(uint){
        return IERC20(uniswapPair).balanceOf(address(this));
    }

    function getUniswapPoolTokenSupply() public view returns(uint){
        return IERC20(uniswapPair).totalSupply();
    }

    function getUniswapPoolReserves() public view returns(uint112 reserve0, uint112 reserve1){
        (reserve0, reserve1, ) = IUniswapV2Pair(uniswapPair).getReserves();
    }

    function getDalpProportionalReserves() public view returns(uint reserve0Share, uint reserve1Share){
        uint256 totalLiquidityTokens = getUniswapPoolTokenSupply();
        uint256 contractLiquidityTokens = getUniswapPoolTokenHoldings();
        (uint112 reserve0, uint112 reserve1) = getUniswapPoolReserves();

        require(totalLiquidityTokens < MAX_UINT112, "UINT112 overflow");
        require(contractLiquidityTokens < MAX_UINT112, "UINT112 overflow");

        uint112 totalLiquidityTokensCasted = uint112(totalLiquidityTokens); // much lower
        uint112 contractLiquidityTokensCasted = uint112(contractLiquidityTokens); // much higher

        // underlying liquidity of contract's pool tokens
        // returns underlying reserves holding of this contract for each asset
        reserve0Share = FixedPoint.encode(reserve0).div(contractLiquidityTokensCasted).mul(totalLiquidityTokens).decode144();
        reserve1Share = FixedPoint.encode(reserve1).div(contractLiquidityTokensCasted).mul(totalLiquidityTokens).decode144();
    }


    //----------------------------------------
    // Internal functions
    //----------------------------------------
  

    /**
     * @notice Add liquidity to a Uniswap pool with DALP controlled assets
     * @param tokenA First token in the Uniswap pair
     * @param tokenB Second token in the Uniswap pair
     * TODO: Track token dust left over from swaps and adding liquidity
     */
    function addUniswapV2Liquidity(address tokenA, address tokenB) internal {
        // Get amount of token A required for adding liquidity
        uint amountAOut = getEquivalentAmountForUniswapV2(WETH, tokenA, address(this).balance);
        uint[] memory amountsA = swapForTokens(tokenA, address(this).balance / 2, amountAOut / 2);

        require(amountsA[1] <= MAX_UINT112, "DALPManager/overflow");
        uint112 amountADesired = uint112(amountsA[1]);

        // Get amount of token B required for adding liquidity
        uint amountBOut = getEquivalentAmountForUniswapV2(tokenA, tokenB, amountADesired);
        uint[] memory amountsB = swapForTokens(tokenB, address(this).balance, amountBOut);

        require(amountsB[1] <= MAX_UINT112, "DALPManager/overflow");
        uint112 amountBDesired = uint112(amountsB[1]);

        // Approve tokens for transfer to Uniswap pair
        IERC20(tokenA).safeApprove(address(uniswapRouter), amountADesired); 
        IERC20(tokenB).safeApprove(address(uniswapRouter), amountBDesired); 

        (uint amountA, uint amountB, uint liquidity) = uniswapRouter.addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountADesired - FixedPoint.encode(amountADesired).div(UNISWAP_V2_SLIPPAGE_LIMIT).decode(),
            amountBDesired - FixedPoint.encode(amountBDesired).div(UNISWAP_V2_SLIPPAGE_LIMIT).decode(),
            address(this),
            now + UNISWAP_V2_DEADLINE_DELTA // solhint-disable-line not-rely-on-time
        );

        emit AddUniswapLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountA,
            amountB,
            liquidity
        );
    }

    /**
     * @notice Swap DALP ETH for tokens
     * @param token The token address
     * @param amountInMax The maximum amount of ETH to swap
     * @param amountOut The number of tokens to receive
     * @return A two element array of the ETH sent and the tokens received
     */
    function swapForTokens(
        address token,
        uint amountInMax, // solhint-disable-line no-unused-vars
        uint amountOut
    )
        internal
        returns (uint[] memory)
    {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = token;

        // solhint-disable-next-line indent, bracket-align
        return uniswapRouter.swapExactETHForTokens{value: amountInMax}(
            amountOut,
            path,
            address(this), 
            now + UNISWAP_V2_DEADLINE_DELTA // solhint-disable-line not-rely-on-time
        );
    }

    //----------------------------------------
    // Internal views
    //----------------------------------------

    function _calculateMintAmount(uint ethValue) private returns (uint mintAmount) {
        (uint reserve0Share, uint reserve1Share) = getDalpProportionalReserves();
        IUniswapV2Pair pair = getUniswapPair(activeTokenPair);

        address token0 = pair.token0();
        address token1 = pair.token1();
        oracle.update(token0);
        oracle.update(token1);

        uint valueToken0 = oracle.consult(token0, reserve0Share);
        uint valueToken1 = oracle.consult(token1, reserve1Share);

        uint decimals = dalp.decimals();
        uint pricePerToken = (valueToken0.add(valueToken1)).mul(decimals).div(dalp.totalSupply());
        mintAmount = ethValue.mul(decimals).div(pricePerToken);
    }

    /**
     * @notice Get the amount of token B that is equivalent to the given amount of token A
     * @param tokenA The address of token A
     * @param tokenB The address of token B
     * @param amountA The amount of token A
     * @return The equivalent amount of token B
     */
    function getEquivalentAmountForUniswapV2(address tokenA, address tokenB, uint amountA)
        internal
        view
        returns (uint)
    {
        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(
            uniswapRouter.factory(),
            tokenA,
            tokenB
        );

        return uniswapRouter.quote(amountA, reserveA, reserveB);
    }

    //----------------------------------------
    // Utils
    //----------------------------------------

    // For v1 of DALP, DALPManager only contributes liquidity to WETH pairs
    function setActiveTokenPair(address _token1) public onlyOwner {
        activeTokenPair = _token1; //
    }

    function setUniswapPair(address _uniswapPair) public onlyOwner {
        uniswapPair = _uniswapPair;
    }

    // need to know which liquidity network
    // need to know which liquidity pair
    // need to know pair addresses
    // function addLiquidityPool(){
        
    // }

    function getUniswapPair(address token) public view returns(IUniswapV2Pair pair){
        pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, WETH, token));
    }
}
