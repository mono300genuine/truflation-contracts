// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface ITfiFarming {
    function stake(uint256 amount) external;

    function unstake(uint256 amount) external;
}
