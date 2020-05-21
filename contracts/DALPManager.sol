pragma solidity ^0.6.6;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {FixedPoint} from "@uniswap/lib/contracts/libraries/FixedPoint.sol";
import {IWETH} from "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
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

    uint112 private constant _MAX_UINT112 = uint112(-1);
    uint private constant _UNISWAP_V2_DEADLINE_DELTA = 15 minutes;

    // Limit slippage to 0.5%
    uint112 private constant _UNISWAP_V2_SLIPPAGE_LIMIT = 200;

    // token DALP is currently provisioning liquidity for
    // the WETH<=>activeTokenPair is current Uniswap pair
    // ex: DAI address
    address private activeTokenPair;

    // address of uniswap pair pool
    address private uniswapPair;


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

    constructor(IUniswapV2Router01 _uniswapRouter, OracleManager _oracle) public {
        uniswapRouter = _uniswapRouter;
        WETH = _uniswapRouter.WETH();
        oracle = _oracle;
    }

    //----------------------------------------
    // Receive function
    //----------------------------------------

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

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
     * @dev The larger the discrepancy between WETH <-> token pairs and the token <-> token pair,
     *      the more ETH will be left behind after adding liquidity.
     * @param tokenA First token in the Uniswap pair
     * @param tokenB Second token in the Uniswap pair
     */
    function _addUniswapV2Liquidity(address tokenA, address tokenB) internal {
        require(address(this).balance > 0, "DALPManager/insufficient-balance");

        uint112 amountADesired;
        uint112 amountBDesired;

        if (tokenA == _WETH || tokenB == _WETH) {
            // Get amount desired for a WETH <-> token pair
            (
                uint112 amountETHDesired,
                uint112 amountTokenDesired
            ) = _getAmountDesiredForWETHPairUniswapV2(tokenA == _WETH ? tokenB : tokenA);

            (amountADesired, amountBDesired) = tokenA == _WETH
                ? (amountETHDesired, amountTokenDesired)
                : (amountTokenDesired, amountETHDesired);
        } else {
            // Get amount desired for a token <-> token pair
            (amountADesired, amountBDesired) = _getAmountDesiredForTokenPairUniswapV2(
                tokenA,
                tokenB
            );
        }

        // Approve tokens for transfer to Uniswap pair
        IERC20(tokenA).safeApprove(address(_uniswapRouter), amountADesired);
        IERC20(tokenB).safeApprove(address(_uniswapRouter), amountBDesired);

        (uint amountA, uint amountB, uint liquidity) = _uniswapRouter.addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountADesired - (
                FixedPoint
                    .encode(amountADesired)
                    .div(_UNISWAP_V2_SLIPPAGE_LIMIT)
                    .decode()
            ),
            amountBDesired - (
                FixedPoint
                    .encode(amountBDesired)
                    .div(_UNISWAP_V2_SLIPPAGE_LIMIT)
                    .decode()
            ),
            address(this),
            now + _UNISWAP_V2_DEADLINE_DELTA // solhint-disable-line not-rely-on-time
        );

        // Swap token A dust to WETH
        if (tokenA != _WETH) {
            uint amountAIn = IERC20(tokenA).balanceOf(address(this));

            if (amountAIn > 0) {
                _swapTokensForWETH(tokenA, amountAIn);
            }
        }

        // Swap token B dust to WETH
        if (tokenB != _WETH) {
            uint amountBIn = IERC20(tokenB).balanceOf(address(this));

            if (amountBIn > 0) {
                _swapTokensForWETH(tokenB, amountBIn);
            }
        }

        // Withdraw WETH dust back to ETH
        IWETH(_WETH).withdraw(IERC20(_WETH).balanceOf(address(this)));

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
     * @notice Get the amount of tokens the DALP can afford to add to a Uniswap v2 WETH pair
     * @dev It was necessary to refactor this code out of `_addUniswapV2Liquidity` to avoid a
     *      "Stack too deep" error.
     * @param token The token paired with WETH
     * @return The desired amount of WETH and tokens
     */
    function _getAmountDesiredForWETHPairUniswapV2(address token)
        internal
        returns (uint112, uint112)
    {
        // Get maximum amount of tokens that can be swapped with half the ETH balance
        uint totalETH = address(this).balance;
        uint amountETH = totalETH / 2;
        uint amountTokenOut = _getAmountOutForUniswapV2(_WETH, token, totalETH - amountETH);

        // Get the balanced amounts for the WETH pair that is less than the maximum swap amount
        (uint amountETHBalanced, uint amountTokenBalanced) = _getBalancedAmountsForUniswapV2(
            _WETH,
            token,
            amountETH,
            amountTokenOut
        );

        // Wrap ETH for WETH
        IWETH(_WETH).deposit{value: amountETHBalanced}();

        // Swap for tokens
        uint[] memory amountsToken = _swapForTokens(
            token,
            address(this).balance,
            amountTokenBalanced
        );

        // Amounts need to be rebalanced because the reserves are changed from the swap
        (amountETHBalanced, amountTokenBalanced) = _getBalancedAmountsForUniswapV2(
            _WETH,
            token,
            amountETHBalanced,
            amountsToken[1]
        );

        require(amountETHBalanced <= _MAX_UINT112, "DALPManager/overflow");
        uint112 amountETHDesired = uint112(amountETHBalanced);

        require(amountTokenBalanced <= _MAX_UINT112, "DALPManager/overflow");
        uint112 amountTokenDesired = uint112(amountTokenBalanced);

        return (amountETHDesired, amountTokenDesired);
    }

    /**
     * @notice Get the amount of tokens the DALP can afford to add to a Uniswap v2 pair
     * @dev It was necessary to refactor this code out of `_addUniswapV2Liquidity` to avoid a
     *      "Stack too deep" error.
     * @param tokenA First token in the Uniswap pair
     * @param tokenB Second token in the Uniswap pair
     * @return The desired amount of token A and token B
     */
    function _getAmountDesiredForTokenPairUniswapV2(address tokenA, address tokenB)
        internal
        returns (uint112, uint112)
    {
        // Get maximum amount of tokens that can be swapped with half the ETH balance
        uint amountAOut = _getAmountOutForUniswapV2(_WETH, tokenA, address(this).balance / 2);
        uint amountBOut = _getAmountOutForUniswapV2(
            _WETH,
            tokenB,
            address(this).balance - (address(this).balance / 2)
        );

        // Get the balanced amounts for the target pair that is less than the maximum swap amount
        (uint amountABalanced, uint amountBBalanced) = _getBalancedAmountsForUniswapV2(
            tokenA,
            tokenB,
            amountAOut,
            amountBOut
        );

        // Swap for token A
        uint[] memory amountsA = _swapForTokens(
            tokenA,
            address(this).balance / 2,
            amountABalanced
        );
        require(amountsA[1] <= _MAX_UINT112, "DALPManager/overflow");
        uint112 amountADesired = uint112(amountsA[1]);

        // Swap for token B
        uint[] memory amountsB = _swapForTokens(tokenB, address(this).balance, amountBBalanced);
        require(amountsB[1] <= _MAX_UINT112, "DALPManager/overflow");
        uint112 amountBDesired = uint112(amountsB[1]);

        return (amountADesired, amountBDesired);
    }

    /**
     * @notice Swap DALP ETH for tokens
     * @param token The token address
     * @param amountInMax The maximum amount of ETH to swap
     * @param amountOut The number of tokens to receive
     * @return A two element array of the ETH sent and the tokens received
     */
    function _swapForTokens(address token, uint amountInMax, uint amountOut)
        internal
        returns (uint[] memory)
    {
        address[] memory path = new address[](2);
        path[0] = _WETH;
        path[1] = token;

        return _uniswapRouter.swapETHForExactTokens{value: amountInMax}(
            amountOut,
            path,
            address(this), 
            now + _UNISWAP_V2_DEADLINE_DELTA // solhint-disable-line not-rely-on-time
        );
    }

    /**
     * @notice Swap DALP tokens for WETH
     * @notice Used to clean up token dust after adding liquidity
     * @param token The token to swap for WETH
     * @param amountIn The amount of tokens to swap
     * @return A two element array of the tokens sent and the WETH received
     */
    function _swapTokensForWETH(address token, uint amountIn) internal returns (uint[] memory) {
        uint amountOut = _getAmountOutForUniswapV2(token, _WETH, amountIn);
        require(amountOut <= _MAX_UINT112, "DALPManager/overflow");
        uint amountOutMin = amountOut - (
            FixedPoint
                .encode(uint112(amountOut))
                .div(_UNISWAP_V2_SLIPPAGE_LIMIT)
                .decode()
        );

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = _WETH;

        IERC20(token).safeApprove(address(_uniswapRouter), amountIn);

        return _uniswapRouter.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this), 
            now + _UNISWAP_V2_DEADLINE_DELTA // solhint-disable-line not-rely-on-time
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
     * @notice Get balanced token amounts for adding liquidity to a Uniswap v2 pair
     * @param tokenA The address of token A
     * @param tokenB The address of token B
     * @param amountA The amount of token A available
     * @param amountB The amount of token B available
     * @return The balanced amounts for token A and B
     */
    function _getBalancedAmountsForUniswapV2(
        address tokenA,
        address tokenB,
        uint amountA,
        uint amountB
    )
        internal
        view
        returns (uint, uint)
    {
        uint amountBBalanced = _getEquivalentAmountForUniswapV2(tokenA, tokenB, amountA);

        if (amountBBalanced > amountB) {
            amountBBalanced = amountB;
        } else if (amountBBalanced == 0) {
            return (amountA, amountB);
        }

        uint amountABalanced = _getEquivalentAmountForUniswapV2(tokenB, tokenA, amountBBalanced);

        return (amountABalanced, amountBBalanced);
    }

    /**
     * @notice Get the amount of token B that is equivalent to the given amount of token A
     * @param tokenA The address of token A
     * @param tokenB The address of token B
     * @param amountA The amount of token A
     * @return The equivalent amount of token B, returns 0 if the token pair has no reserves
     */
    function _getEquivalentAmountForUniswapV2(address tokenA, address tokenB, uint amountA)
        internal
        view
        returns (uint)
    {
        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(
            _uniswapRouter.factory(),
            tokenA,
            tokenB
        );

        if (reserveA == 0 && reserveB == 0) {
            return 0;
        }

        return _uniswapRouter.quote(amountA, reserveA, reserveB);
    }

    /**
     * @notice Get the amount of token B that can be swapped for the given amount of token A
     * @param tokenA The address of token A
     * @param tokenB The address of token B
     * @param amountInA The amount of token A
     * @return The amount of token B that can be swapped for token A
     */
    function _getAmountOutForUniswapV2(address tokenA, address tokenB, uint amountInA)
        internal
        view
        returns (uint)
    {
        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(
            _uniswapRouter.factory(),
            tokenA,
            tokenB
        );

        return _uniswapRouter.getAmountOut(amountInA, reserveA, reserveB);
    }

    //----------------------------------------
    // Utils
    //----------------------------------------

    function setActiveTokenPair(address _token1) public onlyOwner {
        activeTokenPair = _token1; //
    }

    function setUniswapPair(address _uniswapPair) public onlyOwner {
        uniswapPair = _uniswapPair;
    }

    function getUniswapPair(address token) public view returns(IUniswapV2Pair pair){
        pair = IUniswapV2Pair(UniswapV2Library.pairFor(_uniswapRouter.factory(), WETH, token));
    }
}
