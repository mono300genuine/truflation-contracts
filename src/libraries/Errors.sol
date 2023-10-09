// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

library Errors {
    error ZeroAddress();
    error ZeroAmount();
    error Forbidden(address sender);
    error InvalidStatus(bytes32 partnerId);
    error InvalidTimestamp();
    error AddLiquidityFailed();
    error LockDoesNotExist(address user);
    error LockExpired(address user);
    error LockExists(address user);
    error ExceedMaxTime();
    error VestingStarted(uint64 tge);
    error VestingNotStarted();
    error InvalidVestingCategory(uint256 id);
    error InvalidVestingInfo(uint256 categoryIdx, uint256 id);
    error InvalidUserVesting();
    error UserVestingAlreadySet(uint256 categoryIdx, uint256 vestingId, address user);
    error UserVestingDoesNotExists(uint256 categoryIdx, uint256 vestingId, address user);
    error MaxAllocationExceed();
    error InvalidAmount();
    error MulticallFailed();
    error AlreadyVested(uint256 categoryIdx, uint256 vestingId, address user);
}
