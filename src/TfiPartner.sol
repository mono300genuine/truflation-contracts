// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/access/Ownable.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IUniswapV2Router01.sol";
import "./interfaces/IStakingRewards.sol";
import "./libraries/Errors.sol";

contract TfiPartner is Ownable {
    using SafeERC20 for IERC20;

    event Initiated(
        bytes32 indexed id,
        uint256 period,
        uint256 startTime,
        address pToken,
        uint256 pTokenAmount,
        address pOwner,
        uint256 tfiAmount
    );

    event Paid(bytes32 indexed id, uint256 pairTokenIn, uint256 lpAmount);

    event Ended(bytes32 indexed id, uint256 tfiTokenOut, uint256 pairTokenOut, uint256 tfiReward);

    event Cancelled(
        bytes32 indexed id, uint256 tfiTokenOut, uint256 pairTokenOut, uint256 pTokenPaid, uint256 tfiReward
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
        uint256 tfiAmount;
        uint256 lpAmount;
        uint256 tfiRewardDebt;
        Status status;
    }

    IUniswapV2Router01 public immutable uniV2Router;
    IERC20 public immutable tfiToken;
    IERC20 public immutable pairToken;
    IERC20 public immutable lpToken;
    IStakingRewards public immutable lpStaking;
    mapping(bytes32 => Subscription) public subscriptions;
    uint256 public totalLpStaked;
    uint256 public accTfiPerLp; // Accumulated TFI reward per LP token;

    constructor(address _tfiToken, address _pairToken, address _lpToken, address _lpStaking, address _uniV2Router) {
        if (
            _tfiToken == address(0) || _pairToken == address(0) || _lpToken == address(0) || _lpStaking == address(0)
                || _uniV2Router == address(0)
        ) {
            revert Errors.ZeroAddress();
        }

        tfiToken = IERC20(_tfiToken);
        pairToken = IERC20(_pairToken);
        lpToken = IERC20(_lpToken);
        lpStaking = IStakingRewards(_lpStaking);
        uniV2Router = IUniswapV2Router01(_uniV2Router);
    }

    function initiate(
        bytes32 id,
        uint256 period,
        uint256 startTime,
        address pToken,
        uint256 pTokenAmount,
        address pOwner,
        uint256 tfiAmount
    ) external {
        _checkOwner();

        if (period == 0 || pTokenAmount == 0 || tfiAmount == 0) revert Errors.ZeroAmount();
        if (startTime < block.timestamp) revert Errors.InvalidTimestamp();
        if (pToken == address(0) || pOwner == address(0)) revert Errors.ZeroAddress();
        if (subscriptions[id].status != Status.None) revert Errors.InvalidStatus(id);

        tfiToken.safeTransferFrom(msg.sender, address(this), tfiAmount);

        subscriptions[id] = Subscription({
            period: period,
            startTime: startTime,
            pToken: pToken,
            pTokenAmount: pTokenAmount,
            pOwner: pOwner,
            tfiAmount: tfiAmount,
            lpAmount: 0,
            tfiRewardDebt: 0,
            status: Status.Initiated
        });

        emit Initiated(id, period, startTime, pToken, pTokenAmount, pOwner, tfiAmount);
    }

    function pay(bytes32 id, uint256 pairTokenMaxIn, uint256 lpTokenMinOut, uint256 deadline) external {
        Subscription storage subscription = subscriptions[id];
        if (subscription.status != Status.Initiated) revert Errors.InvalidStatus(id);
        if (subscription.pOwner != msg.sender) revert Errors.Forbidden(msg.sender);
        if (subscription.startTime < block.timestamp) revert Errors.InvalidTimestamp();

        subscription.status = Status.Active;

        pairToken.safeTransferFrom(msg.sender, address(this), pairTokenMaxIn);
        pairToken.safeApprove(address(uniV2Router), pairTokenMaxIn);
        tfiToken.safeApprove(address(uniV2Router), subscription.tfiAmount);
        (, uint256 pairTokenIn, uint256 lpAmount) = uniV2Router.addLiquidity(
            address(tfiToken),
            address(pairToken),
            subscription.tfiAmount,
            pairTokenMaxIn,
            subscription.tfiAmount,
            0,
            address(this),
            deadline
        );
        if (lpAmount < lpTokenMinOut) revert Errors.AddLiquidityFailed();
        if (pairTokenMaxIn > pairTokenIn) {
            pairToken.safeTransfer(msg.sender, pairTokenMaxIn - pairTokenIn);
        }

        subscription.lpAmount = lpAmount;

        _updateRewardDebt();

        lpToken.safeApprove(address(lpStaking), lpAmount);
        lpStaking.stake(lpAmount);

        totalLpStaked += lpAmount;
        subscription.tfiRewardDebt = lpAmount * accTfiPerLp;

        IERC20(subscription.pToken).safeTransferFrom(msg.sender, address(this), subscription.pTokenAmount);

        emit Paid(id, pairTokenIn, lpAmount);
    }

    function end(bytes32 id, uint256 tfiMinOut, uint256 pairTokenMinOut, uint256 deadline) external {
        _checkOwner();

        Subscription storage subscription = subscriptions[id];
        if (subscription.status != Status.Active) revert Errors.InvalidStatus(id);
        if (subscription.startTime + subscription.period >= block.timestamp) revert Errors.InvalidTimestamp();

        subscription.status = Status.Ended;

        _updateRewardDebt();

        uint256 tfiReward = (subscription.lpAmount * accTfiPerLp - subscription.tfiRewardDebt) / 1e18;

        lpStaking.withdraw(subscription.lpAmount);

        totalLpStaked -= subscription.lpAmount;

        lpToken.safeApprove(address(uniV2Router), subscription.lpAmount);
        (uint256 tfiTokenOut, uint256 pairTokenOut) = uniV2Router.removeLiquidity(
            address(tfiToken),
            address(pairToken),
            subscription.lpAmount,
            tfiMinOut,
            pairTokenMinOut,
            subscription.pOwner,
            deadline
        );

        IERC20(subscription.pToken).safeTransfer(owner(), subscription.pTokenAmount);
        if (tfiReward != 0) {
            tfiToken.safeTransfer(subscription.pOwner, tfiReward);
        }
        emit Ended(id, tfiTokenOut, pairTokenOut, tfiReward);
    }

    function cancel(bytes32 id, uint256 tfiMinOut, uint256 pairTokenMinOut, uint256 deadline) external {
        _checkOwner();

        Subscription storage subscription = subscriptions[id];

        if (subscription.status == Status.Initiated) {
            if (subscription.startTime > block.timestamp) {
                revert Errors.InvalidTimestamp();
            }

            uint256 tfiAmount = subscription.tfiAmount;
            emit Cancelled(id, subscription.tfiAmount, 0, 0, 0);

            delete subscriptions[id];

            tfiToken.safeTransfer(owner(), tfiAmount);
        } else if (subscription.status == Status.Active) {
            if (subscription.startTime + subscription.period < block.timestamp) {
                revert Errors.InvalidTimestamp();
            }

            subscription.status = Status.Cancelled;

            _updateRewardDebt();

            uint256 tfiReward = (subscription.lpAmount * accTfiPerLp - subscription.tfiRewardDebt) / 1e18;

            lpStaking.withdraw(subscription.lpAmount);

            totalLpStaked -= subscription.lpAmount;

            lpToken.safeApprove(address(uniV2Router), subscription.lpAmount);
            (uint256 tfiTokenOut, uint256 pairTokenOut) = uniV2Router.removeLiquidity(
                address(tfiToken),
                address(pairToken),
                subscription.lpAmount,
                tfiMinOut,
                pairTokenMinOut,
                address(this),
                deadline
            );

            tfiToken.safeTransfer(owner(), tfiTokenOut + tfiReward);
            pairToken.safeTransfer(subscription.pOwner, pairTokenOut);

            uint256 spent = subscription.startTime > block.timestamp ? 0 : block.timestamp - subscription.startTime;

            uint256 pTokenPaid = subscription.pTokenAmount * spent / subscription.period;

            IERC20(subscription.pToken).safeTransfer(owner(), pTokenPaid);
            IERC20(subscription.pToken).safeTransfer(subscription.pOwner, subscription.pTokenAmount - pTokenPaid);

            emit Cancelled(id, tfiTokenOut, pairTokenOut, pTokenPaid, tfiReward);
        } else {
            revert Errors.InvalidStatus(id);
        }
    }

    function _updateRewardDebt() internal {
        if (totalLpStaked == 0) return;
        uint256 reward = lpStaking.getReward();
        if (reward != 0) {
            accTfiPerLp += reward * 1e18 / totalLpStaked;
        }
    }
}
