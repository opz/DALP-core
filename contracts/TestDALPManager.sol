pragma solidity ^0.6.6;

import {IUniswapV2Router01} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";

import {DALPManager} from "./DALPManager.sol";
import {OracleManager} from "./OracleManager.sol";

contract TestDALPManager is DALPManager {
    constructor(IUniswapV2Router01 uniswapRouter, OracleManager oracle)
        public
        DALPManager(uniswapRouter, oracle)
    {} // solhint-disable-line no-empty-blocks

    function addUniswapV2Liquidity(address tokenA, address tokenB) external {
        _addUniswapV2Liquidity(tokenA, tokenB);
    }
}
