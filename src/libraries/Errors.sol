// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

library Errors {
    error ZeroAddress();
    error ZeroAmount();
    error Forbidden(address sender);
    error InvalidStatus(bytes32 partnerId);
    error InvalidTimestamp();
    error AddLiquidityFailed();
}
