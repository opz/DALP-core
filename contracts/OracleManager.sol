pragma solidity ^0.6.6;

import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {FixedPoint} from "@uniswap/lib/contracts/libraries/FixedPoint.sol";
import {UniswapV2OracleLibrary} from "@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol";
import {UniswapV2Library} from "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";

contract OracleManager {
    using FixedPoint for *;

    uint public constant PERIOD = 1 hours;

    address private _factory;
    address private _weth;

    struct OraclePairState {
        IUniswapV2Pair pair;
        address token0;
        address token1;
        uint price0CumulativeLast;
        uint price1CumulativeLast;
        uint32 blockTimestampLast;
        FixedPoint.uq112x112 price0Average;
        FixedPoint.uq112x112 price1Average;
    }

    mapping(address => OraclePairState) private _oraclePairs;

    // mapping where you can insert both assets in either order
    // to pull correct oracleState struct
    // mapping[a][b] = struct
    // mapping[b][a] = struct
    // OR...
    // sort in discrete way using some measurement => deterministic output

    // addPair function instead of constructor instantiation
    // addPair is called on the first time liquidity is migrated to a pair

    // update and consult methods need have specified parameters to update/consult correct pair

    // when user mints, manager contract needs to know which token pair is active

    constructor(address factory, address weth) public {
        _factory = factory;
        _weth = weth;
    }

    modifier oraclePairExists(address token) {
        require(getOraclePairExists(token), "Oracle token pair must exist");
        _;
    }

    modifier oraclePairExistsOrIsWETH(address token) {
        require(
            getOraclePairExists(token) || token == _weth,
            "OracleManager/invalid-pair"
        );
        _;
    }

    function update(address token) external oraclePairExists(token) {
        IUniswapV2Pair pair = getUniswapPair(token);
        (uint32 blockTimestamp, uint price0Cumulative, uint price1Cumulative) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(pair));

        OraclePairState storage oraclePair = _oraclePairs[token];    
        uint32 timeElapsed = blockTimestamp - oraclePair.blockTimestampLast; // overflow is desired

        // ensure that at least one full period has passed since the last update
        if (timeElapsed < PERIOD) return;

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        oraclePair.price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - oraclePair.price0CumulativeLast) / timeElapsed));
        oraclePair.price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - oraclePair.price1CumulativeLast) / timeElapsed));

        oraclePair.price0CumulativeLast = price0Cumulative;
        oraclePair.price1CumulativeLast = price1Cumulative;
        oraclePair.blockTimestampLast = blockTimestamp;
    }

    // note this will always return 0 before update has been called successfully for the first time.
    // address token must be non-weth token
    function consult(address token, uint amountIn)
        external
        view
        oraclePairExistsOrIsWETH(token)
        returns (uint)
    {
        if (token == _weth) return amountIn;

        OraclePairState memory oraclePair = _oraclePairs[token];

        return oraclePair.price1Average.mul(amountIn).decode144();
    }

    // add oracle pair: weth<=>token
    function addPair(address token) public {
        require(_oraclePairs[token].blockTimestampLast == 0, "Pair already exists");
        IUniswapV2Pair pair = getUniswapPair(token);
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, "Oracle Manager: NO_RESERVES");

        _oraclePairs[token] = OraclePairState(
            pair,
            pair.token0(),
            pair.token1(),
            pair.price0CumulativeLast(),
            pair.price1CumulativeLast(),
            blockTimestampLast,
            FixedPoint.uq112x112(0),
            FixedPoint.uq112x112(0)
        );
    }

    function getUniswapPair(address token) public view returns (IUniswapV2Pair pair) {
        pair = IUniswapV2Pair(UniswapV2Library.pairFor(_factory, _weth, token));
    }

    function getOraclePairExists(address token) public view returns (bool) {
        return _oraclePairs[token].token1 != address(0);
    }
}
