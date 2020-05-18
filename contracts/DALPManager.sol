pragma solidity ^0.6.6;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {FixedPoint} from "@uniswap/lib/contracts/libraries/FixedPoint.sol";
import {UniswapV2Library} from "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";
import {IUniswapV2Router01} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";

import {DALP} from "./DALP.sol";

contract DALPManager is Ownable {
    //----------------------------------------
    // Type definitions
    //----------------------------------------

    using FixedPoint for *;
    using SafeERC20 for IERC20;

    //----------------------------------------
    // State variables
    //----------------------------------------

    uint112 private constant _MAX_UINT112 = uint112(-1);
    uint private constant _UNISWAP_V2_DEADLINE_DELTA = 15 minutes;

    // Limit slippage to 0.5%
    uint112 private constant _UNISWAP_V2_SLIPPAGE_LIMIT = 200;

    //----------------------------------------
    // State variables
    //----------------------------------------

    DALP public dalp; // DALP token
    IUniswapV2Router01 private immutable _uniswapRouter;
    address private immutable _WETH; // solhint-disable-line var-name-mixedcase

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

    constructor(IUniswapV2Router01 uniswapRouter) public {
        _uniswapRouter = uniswapRouter;
        _WETH = uniswapRouter.WETH();
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
        uint mintAmount = calculateMintAmount();
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

    function calculateMintAmount() public view returns (uint) {
        return 10; // placeholder logic
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
     * TODO: Track token dust left over from swaps and adding liquidity
     */
    function _addUniswapV2Liquidity(address tokenA, address tokenB) internal {
        require(address(this).balance > 0, "DALPManager/insufficient-balance");

        (
            uint112 amountADesired,
            uint112 amountBDesired
        ) = _getAmountDesiredUniswapV2(tokenA, tokenB);

        // Approve tokens for transfer to Uniswap pair
        IERC20(tokenA).safeApprove(address(_uniswapRouter), amountADesired);
        IERC20(tokenB).safeApprove(address(_uniswapRouter), amountBDesired);

        (uint amountA, uint amountB, uint liquidity) = _uniswapRouter.addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountADesired - FixedPoint.encode(amountADesired).div(_UNISWAP_V2_SLIPPAGE_LIMIT).decode(),
            amountBDesired - FixedPoint.encode(amountBDesired).div(_UNISWAP_V2_SLIPPAGE_LIMIT).decode(),
            address(this),
            now + _UNISWAP_V2_DEADLINE_DELTA // solhint-disable-line not-rely-on-time
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
     * @notice Get the amount of tokens the DALP can afford to add to a Uniswap v2 pair
     * @dev It was necessary to refactor this code out of `_addUniswapV2Liquidity` to avoid a
     *      "Stack too deep" error.
     * @param tokenA First token in the Uniswap pair
     * @param tokenB Second token in the Uniswap pair
     * @return The desired amount of token A and token B
     * TODO: Handle ETH pairs
     */
    function _getAmountDesiredUniswapV2(address tokenA, address tokenB)
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
        uint amountBEquiv = _getEquivalentAmountForUniswapV2(tokenA, tokenB, amountAOut);
        if (amountBEquiv > amountBOut) {
            amountBEquiv = amountBOut;
        }
        uint amountAEquiv = _getEquivalentAmountForUniswapV2(tokenB, tokenA, amountBEquiv);

        // Swap for token A
        uint[] memory amountsA = _swapForTokens(tokenA, address(this).balance / 2, amountAEquiv);
        require(amountsA[1] <= _MAX_UINT112, "DALPManager/overflow");
        uint112 amountADesired = uint112(amountsA[1]);

        // Swap for token B
        uint[] memory amountsB = _swapForTokens(tokenB, address(this).balance, amountBEquiv);
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

    //----------------------------------------
    // Internal views
    //----------------------------------------

    /**
     * @notice Get the amount of token B that is equivalent to the given amount of token A
     * @param tokenA The address of token A
     * @param tokenB The address of token B
     * @param amountA The amount of token A
     * @return The equivalent amount of token B
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
}
