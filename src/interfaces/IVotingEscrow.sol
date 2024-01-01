// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IVotingEscrow {
    /// @dev Lockup struct
    struct Lockup {
        uint128 amount; // Locked amount
        uint128 duration; // Lock duration in seconds
        uint128 end; // Lock end timestamp in seconds
        uint256 points; // veTRUF points
        bool isVesting; // True if locked from vesting
    }

    function stakeVesting(uint256 amount, uint256 duration, address to) external returns (uint256 lockupId);

    function unstakeVesting(address user, uint256 lockupId, bool force) external returns (uint256 amount);

    function migrateVestingLock(address oldUser, address newUser, uint256 lockupId)
        external
        returns (uint256 newLockupId);

    function extendVestingLock(address user, uint256 lockupId, uint256 duration) external;

    // Events
    /// Emitted when user staked TRUF or vesting
    event Stake(
        address indexed user, bool indexed isVesting, uint256 lockupId, uint256 amount, uint256 end, uint256 points
    );

    /// Emitted when user unstaked
    event Unstake(
        address indexed user, bool indexed isVesting, uint256 lockupId, uint256 amount, uint256 end, uint256 points
    );

    /// Emitted when lockup migrated to another user (for vesting only)
    event Migrated(address indexed oldUser, address indexed newUser, uint256 oldLockupId, uint256 newLockupId);

    /// Emitted when lockup cancelled (for vesting only)
    event Cancelled(address indexed user, uint256 lockupId, uint256 amount, uint256 points);
}
