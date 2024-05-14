// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IVirtualStakingRewards.sol";

/**
 * @title VirtualStakingRewards
 * @author Truflation Team
 * @dev A contract for distributing rewards to stakers, fork of Synthetix StakingRewards.
 */
contract VirtualStakingRewards is IVirtualStakingRewards, Ownable2Step {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error ZeroAmount();
    error Forbidden(address sender);
    error RewardPeriodNotFinished();
    error DurationTooLong();

    /* ========== STATE VARIABLES ========== */

    address public rewardsDistribution;
    address public operator;

    address public immutable rewardsToken;
    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public rewardsDuration = 7 days;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    /* ========== MODIFIERS ========== */

    modifier onlyRewardsDistribution() {
        if (msg.sender != rewardsDistribution) {
            revert Forbidden(msg.sender);
        }
        _;
    }

    modifier onlyOperator() {
        if (msg.sender != operator) {
            revert Forbidden(msg.sender);
        }
        _;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor(address _rewardsDistribution, address _rewardsToken) {
        if (_rewardsToken == address(0) || _rewardsDistribution == address(0)) {
            revert ZeroAddress();
        }
        rewardsToken = _rewardsToken;
        rewardsDistribution = _rewardsDistribution;
    }

    /* ========== VIEWS ========== */

    /**
     * @dev Get the total supply of staked tokens.
     * @return uint256 The total supply of staked tokens.
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev Get the balance of the specified account.
     * @param account The address of the account.
     * @return uint256 The balance of the account.
     */
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev Get the last time the reward was applicable.
     * @return uint256 The last time the reward was applicable.
     */
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /**
     * @dev Get the reward per token.
     * @return uint256 The reward per token.
     */
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored + (((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / _totalSupply);
    }

    /**
     * @dev Get the amount of rewards earned by the specified account.
     * @param account The address of the account.
     * @return uint256 The amount of rewards earned by the account.
     */
    function earned(address account) public view returns (uint256) {
        return (_balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18 + rewards[account];
    }

    /**
     * @dev Get the total reward for the current duration.
     * @return uint256 The total reward for the current duration.
     */
    function getRewardForDuration() external view returns (uint256) {
        return rewardRate * rewardsDuration;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Stake a certain amount of tokens.
     * @param user The address of the user to stake for.
     * @param amount The amount of tokens to stake.
     */
    function stake(address user, uint256 amount) external updateReward(user) onlyOperator {
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (user == address(0)) {
            revert ZeroAddress();
        }
        _totalSupply += amount;
        _balances[user] += amount;
        emit Staked(user, amount);
    }

    /**
     * @dev Withdraw a certain amount of staked tokens.
     * @param user The address of the user to withdraw for.
     * @param amount The amount of tokens to withdraw.
     */
    function withdraw(address user, uint256 amount) public updateReward(user) onlyOperator {
        if (amount == 0) {
            revert ZeroAmount();
        }
        _totalSupply -= amount;
        _balances[user] -= amount;
        emit Withdrawn(user, amount);
    }

    /**
     * @dev Get rewards for the caller.
     * @param user The address of the user that owns the rewards.
     * @param to The address of the user to send the rewards to.
     * @return reward The amount of rewards to be claimed.
     */
    function getReward(address user, address to) public updateReward(user) onlyOperator returns (uint256 reward) {
        reward = rewards[user];
        if (reward != 0) {
            rewards[user] = 0;
            IERC20(rewardsToken).safeTransfer(to, reward);
            emit RewardPaid(user, to, reward);
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev Notify the contract about the amount of rewards to be distributed.
     * @param reward The amount of rewards to be distributed.
     */
    function notifyRewardAmount(uint256 reward) external onlyRewardsDistribution updateReward(address(0)) {
        IERC20(rewardsToken).safeTransferFrom(msg.sender, address(this), reward);
        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardsDuration;
        }

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
        emit RewardAdded(reward);
    }

    /**
     * @dev Sets the duration of the rewards distribution.
     * @param _rewardsDuration The duration of the rewards distribution.
     */
    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        if (block.timestamp <= periodFinish) {
            revert RewardPeriodNotFinished();
        } else if (_rewardsDuration == 0) {
            revert ZeroAmount();
        } else if (_rewardsDuration > 5 * 365 days) {
            revert DurationTooLong();
        }

        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(_rewardsDuration);
    }

    /**
     * @dev Sets the address of the rewards distributor.
     * @param _rewardsDistribution The address of the rewards distributor.
     */
    function setRewardsDistribution(address _rewardsDistribution) external onlyOwner {
        if (_rewardsDistribution == address(0)) {
            revert ZeroAddress();
        }
        rewardsDistribution = _rewardsDistribution;

        emit RewardsDistributionUpdated(_rewardsDistribution);
    }

    /**
     * @dev Sets the address of the operator.
     * @param _operator The address of the operator.
     */
    function setOperator(address _operator) external onlyOwner {
        if (_operator == address(0)) {
            revert ZeroAddress();
        }
        operator = _operator;

        emit OperatorUpdated(_operator);
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, address indexed to, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event RewardsDistributionUpdated(address indexed rewardsDistribution);
    event OperatorUpdated(address indexed operator);
}
