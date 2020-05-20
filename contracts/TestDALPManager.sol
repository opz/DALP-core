pragma solidity ^0.6.6;

import {IUniswapV2Router01} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";

import {DALPManager} from "./DALPManager.sol";

contract TestDALPManager is DALPManager {
    // solhint-disable-next-line no-empty-blocks
    constructor(IUniswapV2Router01 _uniswapRouter) public DALPManager(_uniswapRouter) {}

    function addUniswapV2Liquidity(address tokenA, address tokenB) external {
        _addUniswapV2Liquidity(tokenA, tokenB);
    }
}
