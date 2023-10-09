// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IVotingEscrow {
    function stakeFor(uint256 amount, uint256 lockupId, uint256 duration, address user) external;

    function unstakeFor(uint256 lockupId, address user) external returns (uint256 amount);

    function extendFor(uint256 lockupId, uint256 duration, address user) external;

    function migrateLocks(address prevUser, address newUser) external;

    function forceCancel(address user) external;
}
