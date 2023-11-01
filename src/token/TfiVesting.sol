// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title TFI vesting contract
 * @author Ryuhei Matsuda
 * @notice Admin register vesting information for users,
 *      and users could lock vesting to veTFI to get voting power and TFI staking rewards
 */
contract TfiVesting is Ownable {
    using SafeERC20 for IERC20;

    /// @dev Emitted when TGE time set
    event TgeTimeSet(uint64 tgeTime);

    /// @dev Emitted when vesting category is set
    event VestingCategorySet(uint256 indexed id, string category, uint256 maxAllocation);

    /// @dev Emitted when vesting info is set
    event VestingInfoSet(uint256 indexed categoryId, uint256 indexed id, VestingInfo info);

    /// @dev Emitted when user vesting info is set
    event UserVestingSet(
        uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, uint256 amount, uint64 startTime
    );

    /// @dev Emitted when admin migrates user's vesting to another address
    event MigrateUser(
        uint256 indexed categoryId, uint256 indexed vestingId, address prevUser, address newUser, uint256 newLockupId
    );

    /// @dev Emitted when admin cancel user's vesting
    event CancelVesting(
        uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, bool giveUnclaimed
    );

    /// @dev Emitted when user claimed vested TFI tokens
    event Claimed(uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, uint256 amount);

    /// @dev Emitted when veTFI token has been set
    event VeTfiSet(address indexed veTFI);

    /// @dev Emitted when user stakes vesting to veTFI
    event Staked(
        uint256 indexed categoryId,
        uint256 indexed vestingId,
        address indexed user,
        uint256 amount,
        uint256 duration,
        uint256 lockupId
    );

    /// @dev Emitted when user increased veTFI staking period or amount
    event IncreasedStaking(
        uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, uint256 amount, uint256 duration
    );

    /// @dev Emitted when user unstakes from veTFI
    event Unstaked(uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, uint256 amount);

    /// @dev Vesting Category struct
    struct VestingCategory {
        string category; // Category name
        uint256 maxAllocation; // Maximum allocation for this category
        uint256 allocated; // Current allocated amount
    }

    /// @dev Vesting info struct
    struct VestingInfo {
        uint64 initialReleasePct; // Initial Release percentage
        uint64 initialReleasePeriod; // Initial release period after TGE
        uint64 cliff; // Cliff period
        uint64 period; // Total period
        uint64 unit; // The period to claim. ex. montlhy or 6 monthly
    }

    /// @dev User vesting info struct
    struct UserVesting {
        uint256 amount; // Total vesting amount
        uint256 claimed; // Total claimed amount
        uint256 locked; // Locked amount at VotingEscrow
        uint64 startTime; // Vesting start time
    }

    uint256 public constant DENOMINATOR = 10000;

    /// @dev TFI token address
    IERC20 public immutable tfiToken;

    /// @dev veTFI token address
    IVotingEscrow public veTFI;

    /// @dev TGE timestamp
    uint64 public tgeTime;

    /// @dev Vesting categories
    VestingCategory[] public categories;

    /// @dev Vesting info per category
    mapping(uint256 => VestingInfo[]) public vestingInfos;

    /// @dev User vesting information (category => info => user address => user vesting)
    mapping(uint256 => mapping(uint256 => mapping(address => UserVesting))) public userVestings;

    /// @dev Vesting lockup ids (category => info => user address => lockup id)
    mapping(uint256 => mapping(uint256 => mapping(address => uint256))) public lockupIds;

    /**
     * @notice TFI Vesting constructor
     * @param _tfiToken TFI token address
     */
    constructor(IERC20 _tfiToken) {
        if (address(_tfiToken) == address(0)) revert Errors.ZeroAddress();

        tfiToken = _tfiToken;
    }

    /**
     * @notice Calcualte claimable amount (total vested amount - previously claimed amount - locked amount)
     * @param categoryId Vesting category id
     * @param vestingId Vesting id
     * @param user user address
     * @return claimableAmount Claimable amount
     */
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
     * @notice Claim available amount
     * @param categoryId category id
     * @param vestingId vesting id
     * @return claimableAmount Claimable amount
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

    /**
     * @notice Stake vesting to veTFI to get voting power and get staking TFI rewards
     * @param categoryId category id
     * @param vestingId vesting id
     * @param amount amount to stake
     * @param duration lock period in seconds
     */
    function stake(uint256 categoryId, uint256 vestingId, uint256 amount, uint256 duration) external {
        if (amount == 0) {
            revert Errors.ZeroAmount();
        }
        if (lockupIds[categoryId][vestingId][msg.sender] != 0) {
            revert Errors.LockExist();
        }

        UserVesting storage userVesting = userVestings[categoryId][vestingId][msg.sender];

        if (amount > userVesting.amount - userVesting.claimed - userVesting.locked) {
            revert Errors.InvalidAmount();
        }

        userVesting.locked += amount;

        tfiToken.safeIncreaseAllowance(address(veTFI), amount);
        uint256 lockupId = veTFI.stakeVesting(amount, duration, msg.sender) + 1;
        lockupIds[categoryId][vestingId][msg.sender] = lockupId;

        emit Staked(categoryId, vestingId, msg.sender, amount, duration, lockupId);
    }

    /**
     * @notice Increase veTFI staking amount and period
     * @param categoryId category id
     * @param vestingId vesting id
     * @param amount amount to increase
     * @param duration lock period from now
     */
    function increaseStaking(uint256 categoryId, uint256 vestingId, uint256 amount, uint256 duration) external {
        uint256 lockupId = lockupIds[categoryId][vestingId][msg.sender];
        if (lockupId == 0) {
            revert Errors.LockDoesNotExist();
        }

        UserVesting storage userVesting = userVestings[categoryId][vestingId][msg.sender];

        if (amount > userVesting.amount - userVesting.claimed - userVesting.locked) {
            revert Errors.InvalidAmount();
        }

        userVesting.locked += amount;

        tfiToken.safeIncreaseAllowance(address(veTFI), amount);
        veTFI.increaseVestingLock(msg.sender, lockupId - 1, amount, duration);

        emit IncreasedStaking(categoryId, vestingId, msg.sender, amount, duration);
    }

    /**
     * @notice Unstake vesting from veTFI
     * @param categoryId category id
     * @param vestingId vesting id
     */
    function unstake(uint256 categoryId, uint256 vestingId) external {
        uint256 lockupId = lockupIds[categoryId][vestingId][msg.sender];
        if (lockupId == 0) {
            revert Errors.LockDoesNotExist();
        }

        uint256 amount = veTFI.unstakeVesting(msg.sender, lockupId - 1, false);

        UserVesting storage userVesting = userVestings[categoryId][vestingId][msg.sender];

        userVesting.locked -= amount;
        delete lockupIds[categoryId][vestingId][msg.sender];

        emit Unstaked(categoryId, vestingId, msg.sender, amount);
    }

    /**
     * @notice Migrate owner of vesting. Used when user lost his private key
     * @dev Only admin can migrate users vesting
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
        newVesting.startTime = prevVesting.startTime;

        uint256 lockupId = lockupIds[categoryId][vestingId][prevUser];
        uint256 newLockupId;

        if (lockupId != 0) {
            newLockupId = veTFI.migrateVestingLock(prevUser, newUser, lockupId - 1) + 1;
            lockupIds[categoryId][vestingId][newUser] = newLockupId;
            delete lockupIds[categoryId][vestingId][prevUser];

            newVesting.locked = prevVesting.locked;
        }
        delete userVestings[categoryId][vestingId][prevUser];

        emit MigrateUser(categoryId, vestingId, prevUser, newUser, newLockupId);
    }

    /**
     * @notice Cancel vesting and force cancel from voting escrow
     * @dev Only admin can cancel users vesting
     * @param categoryId Category id
     * @param vestingId Vesting id
     * @param user user address
     * @param giveUnclaimed Send currently vested, but unclaimed amount to use or not
     */
    function cancelVesting(uint256 categoryId, uint256 vestingId, address user, bool giveUnclaimed)
        external
        onlyOwner
    {
        UserVesting memory userVesting = userVestings[categoryId][vestingId][user];

        if (userVesting.amount == 0) {
            revert Errors.UserVestingDoesNotExists(categoryId, vestingId, user);
        }

        if (userVesting.startTime + vestingInfos[categoryId][vestingId].period <= block.timestamp) {
            revert Errors.AlreadyVested(categoryId, vestingId, user);
        }

        uint256 lockupId = lockupIds[categoryId][vestingId][user];

        if (lockupId != 0) {
            veTFI.unstakeVesting(user, lockupId - 1, true);
            delete lockupIds[categoryId][vestingId][user];
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

        emit CancelVesting(categoryId, vestingId, user, giveUnclaimed);
    }

    /**
     * @notice Set TGE timestamp
     * @dev Only admin can set tge time
     * @param _tgeTime new TGE timestamp in seconds
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
     * @notice Add or modify vesting category
     * @dev Only admin can set vesting category
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
     * @notice Add or modify vesting information
     * @dev Only admin can set vesting info
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
     * @notice Set user vesting amount
     * @dev Only admin can set user vesting
     * @dev It will be failed if it exceeds max allocation
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

        category.allocated += amount;
        category.allocated -= userVesting.amount;
        if (category.allocated > category.maxAllocation) {
            revert Errors.MaxAllocationExceed();
        }

        if (amount < userVesting.claimed + userVesting.locked) {
            revert Errors.InvalidUserVesting();
        }
        userVesting.amount = amount;
        userVesting.startTime = startTime == 0 ? tgeTime : startTime;

        if (userVesting.startTime == 0) {
            revert Errors.InvalidTimestamp();
        }

        emit UserVestingSet(categoryId, vestingId, user, amount, userVesting.startTime);
    }

    /**
     * @notice Set veTFI token
     * @dev Only admin can set veTFI
     * @param _veTFI veTFI token address
     */
    function setVeTfi(address _veTFI) external onlyOwner {
        if (_veTFI == address(0)) {
            revert Errors.ZeroAddress();
        }
        veTFI = IVotingEscrow(_veTFI);

        emit VeTfiSet(_veTFI);
    }

    /**
     * @notice Multicall several functions in single transaction
     * @dev Could be for setting vesting categories, vesting info, and user vesting in single transaction at once
     * @param payloads list of payloads
     */
    function multicall(bytes[] calldata payloads) external {
        uint256 len = payloads.length;
        for (uint256 i; i < len;) {
            (bool success, bytes memory result) = address(this).delegatecall(payloads[i]);
            if (!success) {
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }

            unchecked {
                i += 1;
            }
        }
    }
}
