// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IUniswapV2Router01.sol";
import "./interfaces/IStakingRewards.sol";

/**
 * @title TrufPartner
 * @author Truflation Team
 * @dev A contract for managing subscriptions.
 */
contract TrufPartner is Ownable2Step {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error ZeroAmount();
    error Forbidden(address sender);
    error InvalidTimestamp();
    error InvalidStatus(bytes32 partnerId);
    error AddLiquidityFailed();

    event Initiated(
        bytes32 indexed id,
        uint256 period,
        uint256 startTime,
        address pToken,
        uint256 pTokenAmount,
        address pOwner,
        uint256 trufAmount
    );

    event Paid(bytes32 indexed id, uint256 pairTokenIn, uint256 lpAmount);

    event Ended(bytes32 indexed id, uint256 trufTokenOut, uint256 pairTokenOut, uint256 trufReward);

    event Cancelled(
        bytes32 indexed id, uint256 trufTokenOut, uint256 pairTokenOut, uint256 pTokenPaid, uint256 trufReward
    );

    enum Status {
        None,
        Initiated,
        Active,
        Cancelled,
        Ended
    }

    struct Subscription {
        uint256 period;
        uint256 startTime;
        address pToken;
        uint256 pTokenAmount;
        address pOwner;
        uint256 trufAmount;
        uint256 lpAmount;
        uint256 trufRewardDebt;
        Status status;
    }

    IUniswapV2Router01 public immutable uniV2Router;
    IERC20 public immutable trufToken;
    IERC20 public immutable pairToken;
    IERC20 public immutable lpToken;
    IStakingRewards public immutable lpStaking;
    mapping(bytes32 => Subscription) public subscriptions;
    uint256 public totalLpStaked;
    uint256 public accTrufPerLp;

    constructor(address _trufToken, address _pairToken, address _lpToken, address _lpStaking, address _uniV2Router) {
        if (
            _trufToken == address(0) ||
            _pairToken == address(0) ||
            _lpToken == address(0) ||
            _lpStaking == address(0) ||
            _uniV2Router == address(0)
        ) {
            revert ZeroAddress();
        }

        trufToken = IERC20(_trufToken);
        pairToken = IERC20(_pairToken);
        lpToken = IERC20(_lpToken);
        lpStaking = IStakingRewards(_lpStaking);
        uniV2Router = IUniswapV2Router01(_uniV2Router);

        lpToken.safeIncreaseAllowance(address(uniV2Router), type(uint256).max);
        lpToken.safeIncreaseAllowance(address(lpStaking), type(uint256).max);
        pairToken.safeIncreaseAllowance(address(uniV2Router), type(uint256).max);
        trufToken.safeIncreaseAllowance(address(uniV2Router), type(uint256).max);
    }

    /**
     * @dev Initiates a subscription.
     * @param id Identifier of the subscription.
     * @param period Duration of the subscription.
     * @param startTime Start time of the subscription.
     * @param pToken Address of the paired token.
     * @param pTokenAmount Amount of paired tokens.
     * @param pOwner Address of the paired token owner.
     * @param trufAmount Amount of TRUF tokens.
     */
    function initiate(
        bytes32 id,
        uint256 period,
        uint256 startTime,
        address pToken,
        uint256 pTokenAmount,
        address pOwner,
        uint256 trufAmount
    ) external {
        _checkOwner();

        if (period == 0 || pTokenAmount == 0 || trufAmount == 0) {
            revert ZeroAmount();
        }
        if (startTime < block.timestamp || startTime - block.timestamp > 365 days) revert InvalidTimestamp();
        if (pToken == address(0) || pOwner == address(0)) {
            revert ZeroAddress();
        }
        if (subscriptions[id].status != Status.None) {
            revert InvalidStatus(id);
        }

        trufToken.safeTransferFrom(msg.sender, address(this), trufAmount);

        subscriptions[id] = Subscription({
            period: period,
            startTime: startTime,
            pToken: pToken,
            pTokenAmount: pTokenAmount,
            pOwner: pOwner,
            trufAmount: trufAmount,
            lpAmount: 0,
            trufRewardDebt: 0,
            status: Status.Initiated
        });

        emit Initiated(id, period, startTime, pToken, pTokenAmount, pOwner, trufAmount);
    }

    /**
     * @dev Pays for a subscription, adding liquidity and staking LP tokens.
     * @param id Identifier of the subscription.
     * @param pairTokenMinIn Minimum amount of paired tokens to be deposited.
     * @param pairTokenMaxIn Maximum amount of paired tokens to be deposited.
     * @param lpTokenMinOut Minimum amount of LP tokens expected as output.
     * @param deadline Deadline for the transaction.
     */
    function pay(bytes32 id, uint256 pairTokenMinIn, uint256 pairTokenMaxIn, uint256 lpTokenMinOut, uint256 deadline) external {
        Subscription storage subscription = subscriptions[id];
        if (subscription.status != Status.Initiated) {
            revert InvalidStatus(id);
        }
        if (subscription.pOwner != msg.sender) {
            revert Forbidden(msg.sender);
        }
        if (subscription.startTime < block.timestamp) {
            revert InvalidTimestamp();
        }

        subscription.status = Status.Active;

        pairToken.safeTransferFrom(msg.sender, address(this), pairTokenMaxIn);
        (, uint256 pairTokenIn, uint256 lpAmount) = uniV2Router.addLiquidity(
            address(trufToken),
            address(pairToken),
            subscription.trufAmount,
            pairTokenMaxIn,
            subscription.trufAmount,
            pairTokenMinIn,
            address(this),
            deadline
        );
        if (lpAmount < lpTokenMinOut) revert AddLiquidityFailed();
        if (pairTokenMaxIn > pairTokenIn) {
            pairToken.safeTransfer(msg.sender, pairTokenMaxIn - pairTokenIn);
        }

        subscription.lpAmount = lpAmount;

        _updateRewardDebt();

        lpStaking.stake(lpAmount);

        totalLpStaked += lpAmount;
        subscription.trufRewardDebt = lpAmount * accTrufPerLp;

        IERC20(subscription.pToken).safeTransferFrom(msg.sender, address(this), subscription.pTokenAmount);

        emit Paid(id, pairTokenIn, lpAmount);
    }

    /**
     * @dev Ends a subscription, removes liquidity, and distributes rewards.
     * @param id Identifier of the subscription.
     * @param trufMinOut Minimum amount of TRUF tokens expected as output.
     * @param pairTokenMinOut Minimum amount of paired tokens expected as output.
     * @param deadline Deadline for the transaction.
     */
    function end(bytes32 id, uint256 trufMinOut, uint256 pairTokenMinOut, uint256 deadline) external {
        _checkOwner();

        Subscription storage subscription = subscriptions[id];
        if (subscription.status != Status.Active) {
            revert InvalidStatus(id);
        }
        if (subscription.startTime + subscription.period >= block.timestamp) {
            revert InvalidTimestamp();
        }

        subscription.status = Status.Ended;

        _updateRewardDebt();

        uint256 trufReward = (subscription.lpAmount * accTrufPerLp - subscription.trufRewardDebt) / 1e18;

        lpStaking.withdraw(subscription.lpAmount);

        totalLpStaked -= subscription.lpAmount;

        (uint256 trufTokenOut, uint256 pairTokenOut) = uniV2Router.removeLiquidity(
            address(trufToken),
            address(pairToken),
            subscription.lpAmount,
            trufMinOut,
            pairTokenMinOut,
            subscription.pOwner,
            deadline
        );

        IERC20(subscription.pToken).safeTransfer(owner(), subscription.pTokenAmount);
        if (trufReward != 0) {
            trufToken.safeTransfer(subscription.pOwner, trufReward);
        }
        emit Ended(id, trufTokenOut, pairTokenOut, trufReward);
    }

    /**
     * @dev Cancels a subscription and refunds tokens to the subscriber.
     * @param id Identifier of the subscription.
     * @param trufMinOut Minimum amount of TRUF tokens expected as output.
     * @param pairTokenMinOut Minimum amount of paired tokens expected as output.
     * @param deadline Deadline for the transaction.
     */
    function cancel(bytes32 id, uint256 trufMinOut, uint256 pairTokenMinOut, uint256 deadline) external {
        _checkOwner();

        Subscription storage subscription = subscriptions[id];

        if (subscription.status == Status.Initiated) {
            if (subscription.startTime > block.timestamp) {
                revert InvalidTimestamp();
            }

            uint256 trufAmount = subscription.trufAmount;
            emit Cancelled(id, subscription.trufAmount, 0, 0, 0);

            delete subscriptions[id];

            trufToken.safeTransfer(owner(), trufAmount);
        } else if (subscription.status == Status.Active) {
            if (subscription.startTime + subscription.period < block.timestamp) {
                revert InvalidTimestamp();
            }

            subscription.status = Status.Cancelled;

            _updateRewardDebt();

            uint256 trufReward = (subscription.lpAmount * accTrufPerLp - subscription.trufRewardDebt) / 1e18;

            lpStaking.withdraw(subscription.lpAmount);

            totalLpStaked -= subscription.lpAmount;

            (uint256 trufTokenOut, uint256 pairTokenOut) = uniV2Router.removeLiquidity(
                address(trufToken),
                address(pairToken),
                subscription.lpAmount,
                trufMinOut,
                pairTokenMinOut,
                address(this),
                deadline
            );

            trufToken.safeTransfer(owner(), trufTokenOut + trufReward);
            pairToken.safeTransfer(subscription.pOwner, pairTokenOut);

            uint256 spent = subscription.startTime > block.timestamp ? 0 : block.timestamp - subscription.startTime;

            uint256 pTokenPaid = (subscription.pTokenAmount * spent) / subscription.period;

            IERC20(subscription.pToken).safeTransfer(owner(), pTokenPaid);
            IERC20(subscription.pToken).safeTransfer(subscription.pOwner, subscription.pTokenAmount - pTokenPaid);

            emit Cancelled(id, trufTokenOut, pairTokenOut, pTokenPaid, trufReward);
        } else {
            revert InvalidStatus(id);
        }
    }

    /**
     * @dev Updates the reward debt based on total LP tokens staked.
     */
    function _updateRewardDebt() internal {
        if (totalLpStaked == 0) return;
        uint256 reward = lpStaking.getReward();
        if (reward != 0) {
            accTrufPerLp += (reward * 1e18) / totalLpStaked;
        }
    }
}
