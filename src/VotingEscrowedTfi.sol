// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/access/Ownable.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin/security/ReentrancyGuard.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IStakingRewards.sol";
import "./libraries/Errors.sol";

contract VotingEscrowedTfi is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event Deposit(
        address indexed user,
        uint256 value,
        uint256 lockTime,
        DepositType depositType,
        uint256 ts
    );
    event Withdraw(address indexed user, uint256 value, uint256 ts);

    struct Point {
        int128 bias;
        int128 slope; // - dweight / dt
        uint256 ts;
        uint256 blk; // block
    }

    struct LockedBalance {
        int128 amount;
        uint256 end;
    }

    enum DepositType {
        DEPOSIT_FOR_TYPE,
        CREATE_LOCK_TYPE,
        INCREASE_LOCK_AMOUNT,
        INCREASE_UNLOCK_TIME
    }

    uint256 public constant WEEK = 7 * 86400;
    uint256 public constant MAXTIME = 3 * 365 * 86400; // 3 years
    uint256 public constant MULTIPLIER = 1e18;

    address public immutable tfiToken;

    mapping(address => LockedBalance) public locked;
    uint256 public epoch;
    Point[] public pointHistory;
    mapping(address => Point[]) public userPointHistory;
    mapping(address => uint256) public userPointEpoch;
    mapping(uint256 => int128) public slopeChanges;

    address public controller;
    bool public transferEnabled;

    constructor(address _tfiToken) ERC20("Voting Escorw TFI", "veTFI") {
        if (_tfiToken == address(0)) {
            revert Errors.ZeroAddress();
        }

        tfiToken = _tfiToken;

        pointHistory.push(
            Point({bias: 0, slope: 0, blk: block.number, ts: block.timestamp})
        );
    }

    function getLastUserSlope(
        address user
    ) external view returns (int128 slope) {
        uint256 uepoch = userPointEpoch[user];
        if (userPointHistory[user].length > uepoch) {
            slope = userPointHistory[user][uepoch].slope;
        }
    }

    function userPointHistoryTs(
        address user,
        uint256 idx
    ) external view returns (uint256 ts) {
        ts = userPointHistory[user][idx].ts;
    }

    function _checkpoint(
        address user,
        LockedBalance memory oldLocked,
        LockedBalance memory newLocked
    ) internal {
        Point memory uOld;
        Point memory uNew;

        int128 oldDslope;
        int128 newDslope;
        uint256 _epoch = epoch;

        if (user != address(0)) {
            if (oldLocked.end > block.timestamp && oldLocked.amount != 0) {
                uOld.slope = oldLocked.amount / int128(uint128(MAXTIME));
                uOld.bias =
                    uOld.slope *
                    int128(uint128(oldLocked.end - block.timestamp));
            }
            if (newLocked.end > block.timestamp && newLocked.amount != 0) {
                uNew.slope = newLocked.amount / int128(uint128(MAXTIME));
                uNew.bias =
                    uNew.slope *
                    int128(uint128(newLocked.end - block.timestamp));
            }

            oldDslope = slopeChanges[oldLocked.end];
            if (newLocked.end != 0) {
                if (newLocked.end == oldLocked.end) {
                    newDslope = oldDslope;
                } else {
                    newDslope = slopeChanges[newLocked.end];
                }
            }
        }

        Point memory lastPoint = Point({
            bias: 0,
            slope: 0,
            ts: block.timestamp,
            blk: block.number
        });
        if (_epoch != 0) {
            lastPoint = pointHistory[_epoch];
        }
        uint256 lastCheckpoint = lastPoint.ts;

        Point memory initialLastPoint = lastPoint;
        uint256 blockSlope;
        if (block.timestamp > lastPoint.ts) {
            blockSlope =
                (MULTIPLIER * (block.number - lastPoint.blk)) /
                (block.timestamp - lastPoint.ts);
        }

        uint256 ti = (lastCheckpoint / WEEK) * WEEK;

        /// TODO
    }

    function _depositFor(
        address user,
        uint256 amount,
        uint256 unlockTime,
        LockedBalance storage lockedBalance,
        DepositType depositType
    ) internal {}

    function depositFor(address user, uint256 amount) external nonReentrant {
        if (amount == 0) {
            revert Errors.ZeroAmount();
        }
        LockedBalance storage lockedBalance = locked[user];

        if (lockedBalance.amount == 0) {
            revert Errors.LockDoesNotExist(user);
        }
        if (lockedBalance.end <= block.timestamp) {
            revert Errors.LockExpired(user);
        }

        _depositFor(
            user,
            amount,
            0,
            lockedBalance,
            DepositType.DEPOSIT_FOR_TYPE
        );
    }

    function createLock(
        uint256 amount,
        uint256 unlockTime
    ) external nonReentrant {
        // TODO: check not contract

        if (amount == 0) {
            revert Errors.ZeroAmount();
        }

        uint256 _unlockTime = (unlockTime / WEEK) * WEEK;
        LockedBalance storage lockedBalance = locked[msg.sender];

        if (lockedBalance.amount != 0) {
            revert Errors.LockExists(msg.sender);
        }
        if (_unlockTime <= block.timestamp) {
            revert Errors.InvalidTimestamp();
        }
        if (_unlockTime > block.timestamp + MAXTIME) {
            revert Errors.ExceedMaxTime();
        }

        _depositFor(
            msg.sender,
            amount,
            _unlockTime,
            lockedBalance,
            DepositType.CREATE_LOCK_TYPE
        );
    }

    function increaseAmount(uint256 amount) external nonReentrant {
        if (amount == 0) {
            revert Errors.ZeroAmount();
        }
        LockedBalance storage lockedBalance = locked[msg.sender];

        if (lockedBalance.amount == 0) {
            revert Errors.LockDoesNotExist(msg.sender);
        }
        if (lockedBalance.end <= block.timestamp) {
            revert Errors.LockExpired(msg.sender);
        }

        _depositFor(
            msg.sender,
            amount,
            0,
            lockedBalance,
            DepositType.INCREASE_LOCK_AMOUNT
        );
    }

    function increaseUnlockTime(uint256 unlockTime) external nonReentrant {
        LockedBalance storage lockedBalance = locked[msg.sender];

        if (lockedBalance.amount == 0) {
            revert Errors.LockDoesNotExist(msg.sender);
        }
        if (lockedBalance.end <= block.timestamp) {
            revert Errors.LockExpired(msg.sender);
        }

        uint256 _unlockTime = (unlockTime / WEEK) * WEEK;

        if (_unlockTime <= lockedBalance.end) {
            revert Errors.InvalidTimestamp();
        }
        if (_unlockTime > block.timestamp + MAXTIME) {
            revert Errors.ExceedMaxTime();
        }

        _depositFor(
            msg.sender,
            0,
            _unlockTime,
            lockedBalance,
            DepositType.INCREASE_UNLOCK_TIME
        );
    }
}
