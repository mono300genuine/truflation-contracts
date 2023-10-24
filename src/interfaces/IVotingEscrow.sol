// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IVotingEscrow {
    function stakeVesting(uint256 amount, uint256 duration, address to) external returns (uint256 lockupId);

    function unstakeVesting(address user, uint256 lockupId, bool force) external returns (uint256 amount);

    function migrateVestingLock(address oldUser, address newUser, uint256 lockupId)
        external
        returns (uint256 newLockupId);

    function increaseVestingLock(address user, uint256 lockupId, uint256 amount, uint256 duration) external;
}
