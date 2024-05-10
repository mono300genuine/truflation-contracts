// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVirtualStakingRewards} from "../interfaces/IVirtualStakingRewards.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";

/**
 * @title VotingEscrowTRUF smart contract (modified from Origin Staking for Truflation)
 * @author Ryuhei Matsuda
 * @notice Provides staking, vote power history, vote delegation, and rewards
 * distribution.
 *
 * The balance received for staking (and thus the voting power and rewards
 * distribution) goes up exponentially by the end of the staked period.
 */
contract VotingEscrowTruf is ERC20Votes, IVotingEscrow {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error ZeroAmount();
    error Forbidden(address sender);
    error InvalidAmount();
    error InvalidAccount();
    error TransferDisabled();
    error MaxPointsExceeded();
    error NoAccess();
    error LockupAlreadyUnstaked();
    error LockupNotEnded();
    error NotIncrease();
    error NotMigrate();
    error TooShort();
    error TooLong();
    error AlreadyEnded();

    /// @dev Minimum staking duration in seconds
    uint256 public immutable minStakeDuration;

    /// @dev Maximum duration
    uint256 public constant MAX_DURATION = 365 days * 3; // 3 years

    /// @dev Lockup list per users
    mapping(address => Lockup[]) public lockups;

    /// @dev TRUF token address
    IERC20 public immutable trufToken; // Must not allow reentrancy

    /// @dev Virtual staking rewards contract address
    IVirtualStakingRewards public immutable stakingRewards;

    /// @dev TRUF Vesting contract address
    address public immutable trufVesting;

    modifier onlyVesting() {
        if (msg.sender != trufVesting) {
            revert Forbidden(msg.sender);
        }
        _;
    }

    // 1. Core Functions

    constructor(address _trufToken, address _trufVesting, uint256 _minStakeDuration, address _stakingRewards)
        ERC20("Voting Escrowed TRUF", "veTRUF")
        ERC20Permit("veTRUF")
    {
        if (_minStakeDuration > MAX_DURATION) {
            revert TooLong();
        }

        trufToken = IERC20(_trufToken);
        trufVesting = _trufVesting;
        minStakeDuration = _minStakeDuration;
        stakingRewards = IVirtualStakingRewards(_stakingRewards);
    }

    function _transfer(address, address, uint256) internal pure override {
        revert TransferDisabled();
    }

    // 2. Staking and Lockup Functions

    /**
     * @notice Stake TRUF to an address that may not be the same as the
     * sender of the funds. This can be used to give staked funds to someone
     * else.
     *
     * @param amount TRUF to lockup in the stake
     * @param duration in seconds for the stake
     * @param to address to receive ownership of the stake
     */
    function stake(uint256 amount, uint256 duration, address to) external {
        _stake(amount, duration, to, false);
    }

    /**
     * @notice Stake TRUF from vesting
     * @param amount TRUF to lockup in the stake
     * @param duration in seconds for the stake
     * @param to address to receive ownership of the stake
     * @return lockupId Lockup id
     */
    function stakeVesting(uint256 amount, uint256 duration, address to)
        external
        onlyVesting
        returns (uint256 lockupId)
    {
        if (to == trufVesting) {
            revert InvalidAccount();
        }
        lockupId = _stake(amount, duration, to, true);
    }

    /**
     * @notice Stake TRUF
     *
     * @param amount TRUF to lockup in the stake
     * @param duration in seconds for the stake
     * @return lockupId Lockup id
     */
    function stake(uint256 amount, uint256 duration) external returns (uint256 lockupId) {
        lockupId = _stake(amount, duration, msg.sender, false);
    }

    /**
     * @dev Internal method used for public staking
     * @param amount TRUF to lockup in the stake
     * @param duration in seconds for the stake
     * @param to address to receive ownership of the stake
     * @param isVesting flag to stake with vested tokens or not
     * @return lockupId Lockup id
     */
    function _stake(uint256 amount, uint256 duration, address to, bool isVesting) internal returns (uint256 lockupId) {
        if (to == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        // duration checked inside previewPoints
        uint256 points = previewPoints(amount, duration);
        uint256 end = block.timestamp + duration;

        lockups[to].push(
            Lockup({
                amount: uint128(amount), // max checked in require above
                duration: uint128(duration),
                end: uint128(end),
                points: points,
                isVesting: isVesting
            })
        );

        trufToken.safeTransferFrom(msg.sender, address(this), amount); // Important that it's sender

        stakingRewards.stake(to, points);
        _mint(to, points);

        if (delegates(to) == address(0)) {
            // Delegate voting power to the receiver, if unregistered
            _delegate(to, to);
        }

        lockupId = lockups[to].length - 1;
        emit Stake(to, isVesting, lockupId, amount, end, points);
    }

    /**
     * @notice Collect staked TRUF for a lockup.
     * @param lockupId the id of the lockup to unstake
     * @return amount TRUF amount returned
     */
    function unstake(uint256 lockupId) external returns (uint256 amount) {
        amount = _unstake(msg.sender, lockupId, false, false);
    }

    /**
     * @notice Collect staked TRUF for a vesting lockup.
     * @param user User address
     * @param lockupId the id of the lockup to unstake
     * @param force True to unstake before maturity (Used to cancel vesting)
     * @return amount TRUF amount returned
     */
    function unstakeVesting(address user, uint256 lockupId, bool force) external onlyVesting returns (uint256 amount) {
        amount = _unstake(user, lockupId, true, force);
    }

    /**
     * @notice Extend lock duration and increase token amount
     *
     * @param lockupId the id of the old lockup to extend
     * @param amount token amount to increase
     * @param duration number of seconds from now to stake for
     */
    function extendLock(uint256 lockupId, uint256 amount, uint256 duration) external {
        _extendLock(msg.sender, lockupId, amount, duration, false);
    }

    /**
     * @notice Extend lock duration and increase token amount for vesting
     *
     * @param user user address
     * @param lockupId the id of the old lockup to extend
     * @param amount token amount to increase
     * @param duration number of seconds from now to stake for
     */
    function extendVestingLock(address user, uint256 lockupId, uint256 amount, uint256 duration) external onlyVesting {
        _extendLock(user, lockupId, amount, duration, true);
    }

    /**
     * @notice Migrate lock to another user
     * @param oldUser Old user address
     * @param newUser New user address
     * @param lockupId the id of the old user's lockup to migrate
     * @return newLockupId the id of new user's migrated lockup
     */
    function migrateVestingLock(address oldUser, address newUser, uint256 lockupId)
        external
        onlyVesting
        returns (uint256 newLockupId)
    {
        if (oldUser == newUser) {
            revert NotMigrate();
        }
        if (newUser == address(0)) {
            revert ZeroAddress();
        }
        Lockup memory oldLockup = lockups[oldUser][lockupId];
        if (!oldLockup.isVesting) {
            revert NoAccess();
        }

        uint256 points = oldLockup.points;
        stakingRewards.withdraw(oldUser, points);
        stakingRewards.getReward(oldUser, newUser);
        _burn(oldUser, points);

        newLockupId = lockups[newUser].length;
        lockups[newUser].push(oldLockup);
        _mint(newUser, points);
        stakingRewards.stake(newUser, points);

        delete lockups[oldUser][lockupId];

        if (delegates(newUser) == address(0)) {
            // Delegate voting power to the new user, if unregistered
            _delegate(newUser, newUser);
        }

        emit Migrated(oldUser, newUser, lockupId, newLockupId);
    }

    /**
     * @notice Claim TRUF staking rewards
     */
    function claimReward() external {
        stakingRewards.getReward(msg.sender, msg.sender);
    }

    /**
     * @notice Preview the number of points that would be returned for the
     * given amount and duration.
     *
     * @param amount TRUF to be staked
     * @param duration number of seconds to stake for
     * @return points staking points that would be returned
     */
    function previewPoints(uint256 amount, uint256 duration) public view returns (uint256 points) {
        if (duration < minStakeDuration) {
            revert TooShort();
        }
        if (duration > MAX_DURATION) {
            revert TooLong();
        }

        points = amount * duration / MAX_DURATION;
    }

    /**
     * @notice Internal function to unstake
     * @param user User address
     * @param lockupId the id of the lockup to unstake
     * @param isVesting flag to stake with vested tokens or not
     * @param force unstake before end period (used to force unstake for vesting lock)
     */
    function _unstake(address user, uint256 lockupId, bool isVesting, bool force) internal returns (uint256 amount) {
        Lockup memory lockup = lockups[user][lockupId];
        if (lockup.isVesting != isVesting) {
            revert NoAccess();
        }
        amount = lockup.amount;
        uint256 end = lockup.end;
        uint256 points = lockup.points;
        if (end == 0) {
            revert LockupAlreadyUnstaked();
        }
        if (!force && block.timestamp < end) {
            revert LockupNotEnded();
        }
        delete lockups[user][lockupId]; // Keeps empty in array, so indexes are stable

        stakingRewards.withdraw(user, points);
        _burn(user, points);
        trufToken.safeTransfer(msg.sender, amount); // Sender is msg.sender

        emit Unstake(user, isVesting, lockupId, amount, end, points);

        if (block.timestamp < end) {
            emit Cancelled(user, lockupId, amount, points);
        }
    }

    /**
     * @notice Extend lock duration
     *
     * @param user user address
     * @param lockupId the id of the old lockup to extend
     * @param amount amount to increase
     * @param duration number of seconds from now to stake for
     * @param isVesting true if called from vesting
     */
    function _extendLock(address user, uint256 lockupId, uint256 amount, uint256 duration, bool isVesting) internal {
        // duration checked inside previewPoints
        Lockup memory lockup = lockups[user][lockupId];
        if (lockup.isVesting != isVesting) {
            revert NoAccess();
        }

        address _user = user;
        uint256 _lockupId = lockupId;
        uint256 _amount = amount;

        uint256 oldAmount = lockup.amount;
        uint256 oldEnd = lockup.end;

        if (oldEnd <= block.timestamp) {
            revert AlreadyEnded();
        }

        uint256 oldPoints = lockup.points;
        uint256 oldDuration = lockup.duration;
        uint256 newEnd = oldEnd + duration;
        uint256 newDuration = oldDuration + duration;

        if (newDuration > MAX_DURATION) {
            revert TooLong();
        }

        uint256 mintAmount = ((oldAmount * duration) + (_amount * (newEnd - block.timestamp))) / MAX_DURATION;

        if (mintAmount == 0) {
            revert NotIncrease();
        }

        uint256 newPoints = oldPoints + mintAmount;
        uint256 newAmount = oldAmount + _amount;

        lockup.amount = uint128(newAmount);
        lockup.end = uint128(newEnd);
        lockup.duration = uint128(newDuration);
        lockup.points = newPoints;

        if (_amount != 0) {
            trufToken.safeTransferFrom(msg.sender, address(this), _amount); // Important that it's sender
        }

        lockups[_user][_lockupId] = lockup;

        stakingRewards.stake(_user, mintAmount);
        _mint(_user, mintAmount);

        emit Unstake(_user, isVesting, _lockupId, oldAmount, oldEnd, oldPoints);
        emit Stake(_user, isVesting, _lockupId, newAmount, newEnd, newPoints);
    }
}
