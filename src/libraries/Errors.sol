// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

library Errors {
    // common
    error ZeroAddress();
    error ZeroAmount();
    error Forbidden(address sender);
    error InvalidTimestamp();
    error InvalidAmount();

    // partner contracts
    error InvalidStatus(bytes32 partnerId);
    error AddLiquidityFailed();

    // vesting
    error VestingStarted(uint64 tge);
    error VestingNotStarted();
    error InvalidVestingCategory(uint256 id);
    error InvalidVestingInfo(uint256 categoryIdx, uint256 id);
    error InvalidUserVesting();
    error UserVestingAlreadySet(uint256 categoryIdx, uint256 vestingId, address user);
    error UserVestingDoesNotExists(uint256 categoryIdx, uint256 vestingId, address user);
    error MaxAllocationExceed();
    error AlreadyVested(uint256 categoryIdx, uint256 vestingId, address user);
    error LockExist();
    error LockDoesNotExist();

    // staking
    error RewardPeriodNotFinished();
    error InsufficientRewards();
}
