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
    error InvalidVesting(uint256 id);
    error UserVestingAlreadySet(address user, uint256 id);
    error UserVestingDoesNotExists(address user, uint256 id);
}
