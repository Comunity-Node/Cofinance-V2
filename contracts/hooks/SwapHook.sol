// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../core/CoFinancePool.sol";

contract SwapHook {
    function preSwap(
        address sender,
        address tokenIn,
        uint256 amountIn,
        address recipient
    ) external virtual returns (bool) {
        return true;
    }

    function postSwap(
        address sender,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOut,
        address recipient
    ) external virtual {
    }
}