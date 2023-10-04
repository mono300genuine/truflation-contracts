// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/Errors.sol";

contract TfiVesting is Ownable {
    using SafeERC20 for IERC20;

    event TgeTimeSet(uint64 tgeTime);
    event VestingInfoSet(uint256 indexed id, VestingInfo info);
    event UserVestingSet(address indexed user, uint256 indexed id, uint amount);
    event MigrateUser(
        address indexed prevUser,
        address indexed newUser,
        uint256 indexed id
    );
    event Claimed(address indexed user, uint256 indexed id, uint amount);

    struct VestingInfo {
        string category;
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
    }

    uint256 public constant DENOMINATOR = 10000;

    // TFI token address
    IERC20 public immutable tfiToken;

    // TGE timestamp
    uint64 public tgeTime;

    // Vesting info per category
    VestingInfo[] public vestingInfos;

    // Vesting amounts per user
    mapping(address => mapping(uint256 => UserVesting)) public userVestings;

    /**
     * TFI Vesting constructor
     * @param _tfiToken TFI token address
     */
    constructor(IERC20 _tfiToken) {
        if (address(_tfiToken) == address(0)) revert Errors.ZeroAddress();

        tfiToken = _tfiToken;
    }

    function claimable(
        address user,
        uint256 id
    ) public view returns (uint256 claimableAmount) {
        if (!_isVestingStarted()) {
            return 0;
        }

        UserVesting memory userVesting = userVestings[user][id];
        uint totalAmount = userVesting.amount;
        if (totalAmount == 0) {
            return 0;
        }

        VestingInfo memory info = vestingInfos[id];

        uint64 timeElapsed = ((uint64(block.timestamp) - tgeTime) / info.unit) *
            info.unit;

        if (timeElapsed < info.initialReleasePeriod) {
            return 0;
        }
        uint256 initialRelease = (totalAmount * info.initialReleasePct) /
            DENOMINATOR;
        uint256 vestedAmount = (
            timeElapsed < info.cliff
                ? 0
                : ((totalAmount - initialRelease) * timeElapsed) / info.period
        ) + initialRelease;

        uint maxClaimable = userVesting.amount - userVesting.locked;
        if (vestedAmount > maxClaimable) {
            vestedAmount = maxClaimable;
        }

        return vestedAmount - userVesting.claimed;
    }

    /**
     * Claim available amount
     * @param id Vesting id
     */
    function claim(uint256 id) public returns (uint claimableAmount) {
        if (!_isVestingStarted()) {
            revert Errors.VestingNotStarted();
        }

        claimableAmount = claimable(msg.sender, id);
        if (claimableAmount == 0) {
            revert Errors.ZeroAmount();
        }

        userVestings[msg.sender][id].claimed += claimableAmount;
        tfiToken.safeTransfer(msg.sender, claimableAmount);

        emit Claimed(msg.sender, id, claimableAmount);
    }

    /**
     * Claim available amounts in batch
     * @param ids list of ids
     */
    function batchClaim(uint256[] calldata ids) external {
        uint length = ids.length;
        for (uint i; i < length; ) {
            claim(ids[i]);
            unchecked {
                i++;
            }
        }
    }

    /**
     * Migrate owner of vesting. Used when user lost his private key
     * @param prevUser previous user address
     * @param newUser new user address
     * @param id vesting id
     */
    function migrateUser(
        address prevUser,
        address newUser,
        uint256 id
    ) external onlyOwner {
        UserVesting storage prevVesting = userVestings[prevUser][id];
        UserVesting storage newVesting = userVestings[newUser][id];

        if (newVesting.amount != 0) {
            revert Errors.UserVestingAlreadySet(newUser, id);
        }
        if (prevVesting.amount == 0) {
            revert Errors.UserVestingDoesNotExists(prevUser, id);
        }

        newVesting.amount = prevVesting.amount;
        newVesting.claimed = prevVesting.claimed;
        newVesting.locked = prevVesting.locked;
        delete userVestings[prevUser][id];

        emit MigrateUser(prevUser, newUser, id);
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
     * Add or modify vesting information
     * @param id id to modify or uint256.max to add new info
     * @param info new vesting info
     */
    function setVestingInfo(
        uint256 id,
        VestingInfo calldata info
    ) public onlyOwner {
        if (id == type(uint256).max) {
            id = vestingInfos.length;
            vestingInfos.push(info);
        } else {
            vestingInfos[id] = info;
        }

        emit VestingInfoSet(id, info);
    }

    /**
     * Register new vesting infos in batch
     * @param infos list of vesting infos
     */
    function batchSetVestingInfo(
        VestingInfo[] calldata infos
    ) external onlyOwner {
        uint length = infos.length;
        for (uint256 i; i < length; ) {
            setVestingInfo(type(uint256).max, infos[i]);
            unchecked {
                i++;
            }
        }
    }

    /**
     * Set user vesting amount
     * @param user user address
     * @param id vesting id
     * @param amount vesting amount
     */
    function setUserVesting(
        address user,
        uint256 id,
        uint256 amount
    ) public onlyOwner {
        if (id >= vestingInfos.length) {
            revert Errors.InvalidVesting(id);
        }

        UserVesting storage userVesting = userVestings[user][id];
        if (userVesting.amount != 0 && _isVestingStarted()) {
            revert Errors.UserVestingAlreadySet(user, id);
        }

        userVesting.amount = amount;

        emit UserVestingSet(user, id, amount);
    }

    /**
     * Set user vesting in batch
     * @param users list of users
     * @param ids list of ids
     * @param amounts list of amounts
     */
    function batchSetUserVesting(
        address[] calldata users,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external {
        uint length = users.length;
        for (uint256 i; i < length; ) {
            setUserVesting(users[i], ids[i], amounts[i]);
            unchecked {
                i++;
            }
        }
    }

    /**
     * Return true if vesting started
     */
    function _isVestingStarted() internal view returns (bool) {
        return tgeTime != 0 && tgeTime <= block.timestamp;
    }
}
