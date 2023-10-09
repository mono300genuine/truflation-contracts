// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {Errors} from "../libraries/Errors.sol";

contract TfiVesting is Ownable {
    using SafeERC20 for IERC20;

    event TgeTimeSet(uint64 tgeTime);
    event VestingCategorySet(uint256 indexed id, string category, uint256 maxAllocation);
    event VestingInfoSet(uint256 indexed categoryId, uint256 indexed id, VestingInfo info);
    event UserVestingSet(
        uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, uint256 amount, uint64 startTime
    );
    event MigrateUser(uint256 indexed categoryId, uint256 indexed vestingId, address prevUser, address newUser);
    event CancelVesting(uint256 indexed categoryId, uint256 indexed vestingId, address indexed user);
    event Claimed(uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, uint256 amount);
    event VeTfiSet(address indexed veTFI);
    event Locked(uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, uint256 amount);
    event Unlocked(uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, uint256 amount);

    struct VestingCategory {
        string category; // Category name
        uint256 maxAllocation; // Maximum allocation for this category
        uint256 allocated; // Current allocated amount
    }

    struct VestingInfo {
        uint64 initialReleasePct; // Initial Release percentage
        uint64 initialReleasePeriod; // Initial release period after TGE
        uint64 cliff; // Cliff period
        uint64 period; // Total period
        uint64 unit; // The period to claim. ex. montlhy or 6 monthly
    }

    struct UserVesting {
        uint256 amount; // Total vesting amount
        uint256 claimed; // Total claimed amount
        uint256 locked; // Locked amount at VotingEscrow
        uint64 startTime; // Vesting start time
    }

    uint256 public constant DENOMINATOR = 10000;

    // TFI token address
    IERC20 public immutable tfiToken;

    // veTFI token address
    IVotingEscrow public veTFI;

    // TGE timestamp
    uint64 public tgeTime;

    // Vesting categories
    VestingCategory[] public categories;

    // Vesting info per category
    mapping(uint256 => VestingInfo[]) public vestingInfos;

    // User vesting information (category => info => user address => user vesting)
    mapping(uint256 => mapping(uint256 => mapping(address => UserVesting))) public userVestings;

    /**
     * TFI Vesting constructor
     * @param _tfiToken TFI token address
     */
    constructor(IERC20 _tfiToken) {
        if (address(_tfiToken) == address(0)) revert Errors.ZeroAddress();

        tfiToken = _tfiToken;
    }

    function claimable(uint256 categoryId, uint256 vestingId, address user)
        public
        view
        returns (uint256 claimableAmount)
    {
        UserVesting memory userVesting = userVestings[categoryId][vestingId][user];
        if (userVesting.startTime > block.timestamp) {
            return 0;
        }
        uint256 totalAmount = userVesting.amount;
        if (totalAmount == 0) {
            return 0;
        }

        VestingInfo memory info = vestingInfos[categoryId][vestingId];

        uint64 timeElapsed = ((uint64(block.timestamp) - userVesting.startTime) / info.unit) * info.unit;

        if (timeElapsed < info.initialReleasePeriod) {
            return 0;
        }
        uint256 initialRelease = (totalAmount * info.initialReleasePct) / DENOMINATOR;
        uint256 vestedAmount = (
            timeElapsed < info.cliff ? 0 : ((totalAmount - initialRelease) * timeElapsed) / info.period
        ) + initialRelease;

        uint256 maxClaimable = userVesting.amount - userVesting.locked;
        if (vestedAmount > maxClaimable) {
            vestedAmount = maxClaimable;
        }
        if (vestedAmount <= userVesting.claimed) {
            return 0;
        }

        return vestedAmount - userVesting.claimed;
    }

    /**
     * Claim available amount
     * @param categoryId category id
     * @param vestingId vesting id
     */
    function claim(uint256 categoryId, uint256 vestingId) public returns (uint256 claimableAmount) {
        claimableAmount = claimable(categoryId, vestingId, msg.sender);
        if (claimableAmount == 0) {
            revert Errors.ZeroAmount();
        }

        userVestings[categoryId][vestingId][msg.sender].claimed += claimableAmount;
        tfiToken.safeTransfer(msg.sender, claimableAmount);

        emit Claimed(categoryId, vestingId, msg.sender, claimableAmount);
    }

    function stake(uint256 categoryId, uint256 vestingId, uint256 amount, uint256 lockupId, uint256 duration)
        external
    {
        if (amount == 0) {
            revert Errors.ZeroAmount();
        }

        UserVesting storage userVesting = userVestings[categoryId][vestingId][msg.sender];

        if (amount > userVesting.amount - userVesting.claimed - userVesting.locked) {
            revert Errors.InvalidAmount();
        }

        userVesting.locked += amount;

        tfiToken.safeIncreaseAllowance(address(veTFI), amount);
        veTFI.stakeFor(amount, lockupId, duration, msg.sender);

        emit Locked(categoryId, vestingId, msg.sender, amount);
    }

    function unstake(uint256 categoryId, uint256 vestingId, uint256 lockupId) external {
        UserVesting storage userVesting = userVestings[categoryId][vestingId][msg.sender];

        uint256 amount = veTFI.unstakeFor(lockupId, msg.sender);

        userVesting.locked -= amount;

        emit Unlocked(categoryId, vestingId, msg.sender, amount);
    }

    /**
     * Migrate owner of vesting. Used when user lost his private key
     * @param categoryId Category id
     * @param vestingId Vesting id
     * @param prevUser previous user address
     * @param newUser new user address
     */
    function migrateUser(uint256 categoryId, uint256 vestingId, address prevUser, address newUser) external onlyOwner {
        UserVesting storage prevVesting = userVestings[categoryId][vestingId][prevUser];
        UserVesting storage newVesting = userVestings[categoryId][vestingId][newUser];

        if (newVesting.amount != 0) {
            revert Errors.UserVestingAlreadySet(categoryId, vestingId, newUser);
        }
        if (prevVesting.amount == 0) {
            revert Errors.UserVestingDoesNotExists(categoryId, vestingId, prevUser);
        }

        newVesting.amount = prevVesting.amount;
        newVesting.claimed = prevVesting.claimed;

        if (prevVesting.locked != 0) {
            veTFI.migrateLocks(prevUser, newUser);
            newVesting.locked = prevVesting.locked;
        }
        delete userVestings[categoryId][vestingId][prevUser];

        emit MigrateUser(categoryId, vestingId, prevUser, newUser);
    }

    /**
     * Cancel vesting and force cancel from voting escrow
     * @param categoryId Category id
     * @param vestingId Vesting id
     * @param user user address
     * @param giveUnclaimed Send currently vested, but unclaimed amount to use or not
     */
    function cancelVesting(uint256 categoryId, uint256 vestingId, address user, bool giveUnclaimed)
        external
        onlyOwner
    {
        UserVesting storage userVesting = userVestings[categoryId][vestingId][user];

        if (userVesting.amount == 0) {
            revert Errors.UserVestingDoesNotExists(categoryId, vestingId, user);
        }

        if (userVesting.startTime + vestingInfos[categoryId][vestingId].period <= block.timestamp) {
            revert Errors.AlreadyVested(categoryId, vestingId, user);
        }

        if (userVesting.locked != 0) {
            veTFI.forceCancel(user);
            userVesting.locked = 0;
        }

        uint256 claimableAmount = claimable(categoryId, vestingId, user);
        if (giveUnclaimed && claimableAmount != 0) {
            tfiToken.safeTransfer(user, claimableAmount);

            userVesting.claimed += claimableAmount;
            emit Claimed(categoryId, vestingId, user, claimableAmount);
        }

        uint256 unvested = userVesting.amount - userVesting.claimed;

        delete userVestings[categoryId][vestingId][user];

        VestingCategory storage category = categories[categoryId];
        category.allocated -= unvested;

        emit CancelVesting(categoryId, vestingId, user);
    }

    /**
     * Set TGE timestamp
     * @param _tgeTime new TGE timestamp
     */
    function setTgeTime(uint64 _tgeTime) external onlyOwner {
        if (tgeTime != 0 && tgeTime < block.timestamp) {
            revert Errors.VestingStarted(tgeTime);
        }

        if (_tgeTime < block.timestamp) {
            revert Errors.InvalidTimestamp();
        }

        tgeTime = _tgeTime;

        emit TgeTimeSet(_tgeTime);
    }

    /**
     * Add or modify vesting category
     * @param id id to modify or uint256.max to add new category
     * @param category new vesting category
     */
    function setVestingCategory(uint256 id, string calldata category, uint256 maxAllocation) public onlyOwner {
        int256 tokenMove;
        if (id == type(uint256).max) {
            id = categories.length;
            categories.push(VestingCategory(category, maxAllocation, 0));
            tokenMove = int256(maxAllocation);
        } else {
            if (categories[id].allocated > maxAllocation) {
                revert Errors.MaxAllocationExceed();
            }
            tokenMove = int256(maxAllocation) - int256(categories[id].maxAllocation);
            categories[id].maxAllocation = maxAllocation;
            categories[id].category = category;
        }

        if (tokenMove > 0) {
            tfiToken.safeTransferFrom(msg.sender, address(this), uint256(tokenMove));
        } else if (tokenMove < 0) {
            tfiToken.safeTransfer(msg.sender, uint256(-tokenMove));
        }

        emit VestingCategorySet(id, category, maxAllocation);
    }

    /**
     * Add or modify vesting information
     * @param categoryIdx category id
     * @param id id to modify or uint256.max to add new info
     * @param info new vesting info
     */
    function setVestingInfo(uint256 categoryIdx, uint256 id, VestingInfo calldata info) public onlyOwner {
        if (id == type(uint256).max) {
            id = vestingInfos[categoryIdx].length;
            vestingInfos[categoryIdx].push(info);
        } else {
            vestingInfos[categoryIdx][id] = info;
        }

        emit VestingInfoSet(categoryIdx, id, info);
    }

    /**
     * Set user vesting amount
     * @param categoryId category id
     * @param vestingId vesting id
     * @param user user address
     * @param startTime zero to start from TGE or non-zero to set up custom start time
     * @param amount vesting amount
     */
    function setUserVesting(uint256 categoryId, uint256 vestingId, address user, uint64 startTime, uint256 amount)
        public
        onlyOwner
    {
        if (categoryId >= categories.length) {
            revert Errors.InvalidVestingCategory(categoryId);
        }
        if (vestingId >= vestingInfos[categoryId].length) {
            revert Errors.InvalidVestingInfo(categoryId, vestingId);
        }

        VestingCategory storage category = categories[categoryId];
        UserVesting storage userVesting = userVestings[categoryId][vestingId][user];

        category.allocated += amount - userVesting.amount;
        if (category.allocated > category.maxAllocation) {
            revert Errors.MaxAllocationExceed();
        }

        if (amount < userVesting.claimed + userVesting.locked) {
            revert Errors.InvalidUserVesting();
        }
        userVesting.amount = amount;
        userVesting.startTime = startTime == 0 ? tgeTime : startTime;

        emit UserVestingSet(categoryId, vestingId, user, amount, userVesting.startTime);
    }

    function setVeTfi(address _veTFI) external onlyOwner {
        if (_veTFI == address(0)) {
            revert Errors.ZeroAddress();
        }
        veTFI = IVotingEscrow(_veTFI);

        emit VeTfiSet(_veTFI);
    }

    function multicall(bytes[] calldata payloads) external {
        uint256 len = payloads.length;
        for (uint256 i; i < len;) {
            (bool success,) = address(this).delegatecall(payloads[i]);
            if (!success) {
                revert Errors.MulticallFailed();
            }

            unchecked {
                i += 1;
            }
        }
    }
}