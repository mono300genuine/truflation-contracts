// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PRBMathUD60x18} from "paulrberg/prb-math/contracts/PRBMathUD60x18.sol";
import {RewardsSource} from "../interfaces/RewardsSource.sol";
import {IVirtualStakingRewards} from "../interfaces/IVirtualStakingRewards.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";

/**
 * @title VotingEscrowTFI smart contract (modified from Origin Staking for Truflation)
 * @author Ryuhei Matsuda
 * @notice Provides staking, vote power history, vote delegation, and rewards
 * distribution.
 *
 * The balance received for staking (and thus the voting power and rewards
 * distribution) goes up exponentially by the end of the staked period.
 */
contract VotingEscrowTfi is ERC20Votes, IVotingEscrow {
    using SafeERC20 for IERC20;

    // 1. Core Storage
    /// @dev start timestamp
    uint256 public immutable epoch; // timestamp
    /// @dev minimum staking duration in seconds
    uint256 public immutable minStakeDuration;

    // 2. Staking and Lockup Storage
    uint256 public constant YEAR_BASE = 18e17;

    /// @dev Maximum duration
    uint256 public constant MAX_DURATION = 365 days * 3; // 3 years

    /// @dev lockup list per users
    mapping(address => Lockup[]) public lockups;

    /// @dev TFI token address
    IERC20 public immutable tfiToken; // Must not allow reentrancy

    /// @dev Virtual staking rewards contract address
    IVirtualStakingRewards public immutable stakingRewards;

    /// @dev TFI Vesting contract address
    address public immutable tfiVesting;

    // Used to track any calls to `delegate()` method. When this isn't
    // set to true, voting powers are delegated to the receiver of the stake
    // when `stake()` or `extend()` method are called.
    // For existing stakers with delegation set, This will remain `false`
    // unless the user calls `delegate()` method.
    mapping(address => bool) public hasDelegationSet;

    modifier onlyVesting() {
        require(msg.sender == tfiVesting, "not vesting");
        _;
    }

    // 1. Core Functions

    constructor(
        address _tfiToken,
        address _tfiVesting,
        uint256 _epoch,
        uint256 _minStakeDuration,
        address _stakingRewards
    ) ERC20("Voting Escrowed TFI", "veTFI") ERC20Permit("veTFI") {
        tfiToken = IERC20(_tfiToken);
        tfiVesting = _tfiVesting;
        epoch = _epoch;
        minStakeDuration = _minStakeDuration;
        stakingRewards = IVirtualStakingRewards(_stakingRewards);
    }

    function _transfer(address, address, uint256) internal override {
        revert("Transfer disabled");
    }

    // 2. Staking and Lockup Functions

    /**
     * @notice Stake TFI to an address that may not be the same as the
     * sender of the funds. This can be used to give staked funds to someone
     * else.
     *
     * If staking before the start of staking (epoch), then the lockup start
     * and end dates are shifted forward so that the lockup starts at the
     * epoch.
     * @param amount TFI to lockup in the stake
     * @param duration in seconds for the stake
     * @param to address to receive ownership of the stake
     */
    function stake(uint256 amount, uint256 duration, address to) external {
        _stake(amount, duration, to, false);
    }

    /**
     * @notice Stake TFI from vesting
     * @param amount TFI to lockup in the stake
     * @param duration in seconds for the stake
     * @param to address to receive ownership of the stake
     * @return lockupId Lockup id
     */
    function stakeVesting(uint256 amount, uint256 duration, address to)
        external
        onlyVesting
        returns (uint256 lockupId)
    {
        lockupId = _stake(amount, duration, to, true);
    }

    /**
     * @notice Stake TFI
     *
     * If staking before the start of staking (epoch), then the lockup start
     * and end dates are shifted forward so that the lockup starts at the
     * epoch.
     *
     * @param amount TFI to lockup in the stake
     * @param duration in seconds for the stake
     * @return lockupId Lockup id
     */
    function stake(uint256 amount, uint256 duration) external returns (uint256 lockupId) {
        lockupId = _stake(amount, duration, msg.sender, false);
    }

    /**
     * @dev Internal method used for public staking
     * @param amount TFI to lockup in the stake
     * @param duration in seconds for the stake
     * @param to address to receive ownership of the stake
     * @param isVesting flag to stake with vested tokens or not
     * @return lockupId Lockup id
     */
    function _stake(uint256 amount, uint256 duration, address to, bool isVesting) internal returns (uint256 lockupId) {
        require(to != address(0), "To the zero address");
        require(amount <= type(uint128).max, "Too much");
        require(amount > 0, "Not enough");

        // duration checked inside previewPoints
        (uint256 points, uint256 end) = previewPoints(amount, duration);
        require(points + totalSupply() <= type(uint192).max, "Max points exceeded");

        lockups[to].push(
            Lockup({
                amount: uint128(amount), // max checked in require above
                end: uint128(end),
                points: points,
                isVesting: isVesting
            })
        );
        stakingRewards.stake(to, points);
        _mint(to, points);
        tfiToken.safeTransferFrom(msg.sender, address(this), amount); // Important that it's sender

        if (!hasDelegationSet[to] && delegates(to) == address(0)) {
            // Delegate voting power to the receiver, if unregistered
            _delegate(to, to);
        }

        lockupId = lockups[to].length - 1;
        emit Stake(to, isVesting, lockupId, amount, end, points);
    }

    /**
     * @notice Collect staked TFI for a lockup.
     * @param lockupId the id of the lockup to unstake
     * @return amount TFI amount returned
     */
    function unstake(uint256 lockupId) external returns (uint256 amount) {
        amount = _unstake(msg.sender, lockupId, false, false);
    }

    /**
     * @notice Collect staked TFI for a vesting lockup.
     * @param user User address
     * @param lockupId the id of the lockup to unstake
     * @param force True to unstake before maturity (Used to cancel vesting)
     * @return amount TFI amount returned
     */
    function unstakeVesting(address user, uint256 lockupId, bool force) external onlyVesting returns (uint256 amount) {
        amount = _unstake(user, lockupId, true, force);
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
        Lockup memory oldLockup = lockups[oldUser][lockupId];
        require(oldLockup.isVesting, "Not vesting");

        require(oldLockup.points != 0, "Old user does not have lock");

        stakingRewards.exit(oldUser);
        uint256 points = oldLockup.points;
        _burn(oldUser, points);

        newLockupId = lockups[newUser].length;
        lockups[newUser].push(oldLockup);
        _mint(newUser, points);
        stakingRewards.stake(newUser, points);

        delete lockups[oldUser][lockupId];

        emit Migrated(oldUser, newUser, lockupId, newLockupId);
    }

    /**
     * @notice Interal function to unstake
     * @param user User address
     * @param lockupId the id of the lockup to unstake
     * @param isVesting flag to stake with vested tokens or not
     * @param force unstake before end period (used to force unstake for vesting lock)
     */
    function _unstake(address user, uint256 lockupId, bool isVesting, bool force) internal returns (uint256 amount) {
        Lockup memory lockup = lockups[user][lockupId];
        require(lockup.isVesting == isVesting, "No access");
        amount = lockup.amount;
        uint256 end = lockup.end;
        uint256 points = lockup.points;
        require(end != 0, "Already unstaked this lockup");
        require(force || block.timestamp >= end, "End of lockup not reached");
        delete lockups[user][lockupId]; // Keeps empty in array, so indexes are stable

        stakingRewards.withdraw(user, points);
        _burn(user, points);
        tfiToken.safeTransfer(msg.sender, amount); // Sender is msg.sender
        emit Unstake(user, isVesting, lockupId, amount, end, points);
    }

    /**
     * @notice Increase lock amount or duration
     *
     * @param lockupId the id of the old lockup to extend
     * @param amount New TFI amount to lock
     * @param duration number of seconds from now to stake for
     */
    function increaseLock(uint256 lockupId, uint256 amount, uint256 duration) external {
        _increaseLock(msg.sender, lockupId, amount, duration, false);
    }

    /**
     * @notice Increase lock amount or duration for vesting
     *
     * @param amount New TFI amount to lock
     * @param duration number of seconds from now to stake for
     */
    function increaseVestingLock(address user, uint256 lockupId, uint256 amount, uint256 duration)
        external
        onlyVesting
    {
        _increaseLock(user, lockupId, amount, duration, true);
    }

    /**
     * @notice Increase lock amount or duration
     *
     * The stake end time is computed from the current time + duration, just
     * like it is for new stakes. So a new stake for seven days duration and
     * an old stake extended with a seven days duration would have the same
     * end.
     *
     * If an extend is made before the start of staking, the start time for
     * the new stake is shifted forwards to the start of staking, which also
     * shifts forward the end date.
     *
     * @param user user address
     * @param lockupId the id of the old lockup to extend
     * @param amount New TFI amount to lock
     * @param duration number of seconds from now to stake for
     * @param isVesting true if called from vesting
     */
    function _increaseLock(address user, uint256 lockupId, uint256 amount, uint256 duration, bool isVesting) internal {
        // duration checked inside previewPoints
        Lockup memory lockup = lockups[user][lockupId];
        require(lockup.isVesting == isVesting, "No access");
        uint256 oldAmount = lockup.amount;
        uint256 oldEnd = lockup.end;
        uint256 oldPoints = lockup.points;

        uint256 newAmount = oldAmount += amount;
        require(newAmount <= type(uint128).max, "Too much");

        if (amount != 0) {
            tfiToken.safeTransferFrom(msg.sender, address(this), amount); // Sender is msg.sender
        }

        (uint256 newPoints, uint256 newEnd) = previewPoints(newAmount, duration);
        require(newEnd >= oldEnd, "New lockup must be longer");
        uint256 mintAmount = newPoints - oldPoints;
        require(newPoints > oldPoints, "Not increase");

        lockup.end = uint128(newEnd);
        lockup.amount = uint128(newAmount);
        lockup.points = newPoints;

        lockups[user][lockupId] = lockup;

        stakingRewards.stake(user, mintAmount);
        _mint(user, mintAmount);
        if (!hasDelegationSet[user] && delegates(user) == address(0)) {
            // Delegate voting power to the receiver, if unregistered
            _delegate(user, user);
        }
        emit Unstake(user, isVesting, lockupId, oldAmount, oldEnd, oldPoints);
        emit Stake(user, isVesting, lockupId, newAmount, newEnd, newPoints);
    }

    /**
     * @notice Preview the number of points that would be returned for the
     * given amount and duration.
     *
     * @param amount TFI to be staked
     * @param duration number of seconds to stake for
     * @return points staking points that would be returned
     * @return end staking period end date
     */
    function previewPoints(uint256 amount, uint256 duration) public view returns (uint256, uint256) {
        require(duration >= minStakeDuration, "Too short");
        require(duration <= MAX_DURATION, "Too long");
        uint256 start = block.timestamp > epoch ? block.timestamp : epoch;
        uint256 end = start + duration;
        uint256 endYearpoc = ((end - epoch) * 1e18) / 365 days;
        uint256 multiplier = PRBMathUD60x18.pow(YEAR_BASE, endYearpoc);
        return ((amount * multiplier) / 1e18, end);
    }

    /**
     * @notice Claim TFI staking rewards
     */
    function claimReward() external {
        stakingRewards.getReward(msg.sender);
    }

    /**
     * @dev Change delegation for `delegator` to `delegatee`.
     *
     * Emits events {DelegateChanged} and {DelegateVotesChanged}.
     */
    function _delegate(address delegator, address delegatee) internal override {
        hasDelegationSet[delegator] = true;
        super._delegate(delegator, delegatee);
    }
}
