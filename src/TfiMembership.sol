// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/access/Ownable.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IUniswapV2Router01.sol";
import "./interfaces/ITfiFarming.sol";
import "./libraries/Errors.sol";

contract TfiMembership is Ownable {
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

    event Ended(bytes32 indexed id, uint256 tfiTokenOut, uint256 pairTokenOut);

    event Cancelled(bytes32 indexed id, uint256 tfiTokenOut, uint256 pairTokenOut, uint256 pTokenPaid);

    enum Status {
        None,
        Initiated,
        Active,
        Cancelled,
        Ended
    }

    struct Membership {
        uint256 period;
        uint256 startTime;
        address pToken;
        uint256 pTokenAmount;
        address pOwner;
        uint256 tfiAmount;
        uint256 lpAmount;
        Status status;
    }

    IUniswapV2Router01 public uniV2Router;
    IERC20 public immutable tfiToken;
    IERC20 public immutable pairToken;
    IERC20 public immutable lpToken;
    ITfiFarming public immutable tfiFarming;
    mapping(bytes32 => Membership) public memberships;

    constructor(address _tfiToken, address _pairToken, address _lpToken, address _farming) {
        if (_tfiToken == address(0) || _pairToken == address(0) || _lpToken == address(0) || _farming == address(0)) {
            revert Errors.ZeroAddress();
        }

        tfiToken = IERC20(_tfiToken);
        pairToken = IERC20(_pairToken);
        lpToken = IERC20(_lpToken);
        tfiFarming = ITfiFarming(_farming);
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
        if (memberships[id].status != Status.None) revert Errors.InvalidStatus(id);

        tfiToken.safeTransferFrom(msg.sender, address(this), tfiAmount);

        memberships[id] = Membership({
            period: period,
            startTime: startTime,
            pToken: pToken,
            pTokenAmount: pTokenAmount,
            pOwner: pOwner,
            tfiAmount: tfiAmount,
            lpAmount: 0,
            status: Status.Initiated
        });

        emit Initiated(id, period, startTime, pToken, pTokenAmount, pOwner, tfiAmount);
    }

    function pay(bytes32 id, uint256 pairTokenMaxIn, uint256 lpTokenMinOut, uint256 deadline) external {
        Membership storage membership = memberships[id];
        if (membership.status != Status.Initiated) revert Errors.InvalidStatus(id);
        if (membership.pOwner != msg.sender) revert Errors.Forbidden(msg.sender);
        if (membership.startTime < block.timestamp) revert Errors.InvalidTimestamp();

        membership.status = Status.Active;

        pairToken.safeTransferFrom(msg.sender, address(this), pairTokenMaxIn);
        pairToken.safeApprove(address(uniV2Router), pairTokenMaxIn);
        tfiToken.safeApprove(address(uniV2Router), membership.tfiAmount);
        (, uint256 pairTokenIn, uint256 lpAmount) = uniV2Router.addLiquidity(
            address(tfiToken),
            address(pairToken),
            membership.tfiAmount,
            pairTokenMaxIn,
            membership.tfiAmount,
            0,
            address(this),
            deadline
        );
        if (lpAmount < lpTokenMinOut) revert Errors.AddLiquidityFailed();
        if (pairTokenMaxIn > pairTokenIn) {
            pairToken.safeTransfer(msg.sender, pairTokenMaxIn - pairTokenIn);
        }

        membership.lpAmount = lpAmount;

        lpToken.safeApprove(address(tfiFarming), lpAmount);
        tfiFarming.stake(lpAmount);

        IERC20(membership.pToken).safeTransferFrom(msg.sender, address(this), membership.pTokenAmount);

        emit Paid(id, pairTokenIn, lpAmount);
    }

    function end(bytes32 id, uint256 tfiMinOut, uint256 pairTokenMinOut, uint256 deadline) external {
        _checkOwner();

        Membership storage membership = memberships[id];
        if (membership.status != Status.Active) revert Errors.InvalidStatus(id);
        if (membership.startTime + membership.period >= block.timestamp) revert Errors.InvalidTimestamp();

        membership.status = Status.Ended;

        tfiFarming.unstake(membership.lpAmount);
        lpToken.safeApprove(address(uniV2Router), membership.lpAmount);
        (uint256 tfiTokenOut, uint256 pairTokenOut) = uniV2Router.removeLiquidity(
            address(tfiToken),
            address(pairToken),
            membership.lpAmount,
            tfiMinOut,
            pairTokenMinOut,
            membership.pOwner,
            deadline
        );

        IERC20(membership.pToken).safeTransfer(owner(), membership.pTokenAmount);
        emit Ended(id, tfiTokenOut, pairTokenOut);
    }

    function cancelMembership(bytes32 id, uint256 tfiMinOut, uint256 pairTokenMinOut, uint256 deadline) external {
        _checkOwner();

        Membership storage membership = memberships[id];
        if (membership.status != Status.Active) revert Errors.InvalidStatus(id);
        if (membership.startTime + membership.period < block.timestamp) {
            revert Errors.InvalidTimestamp();
        }

        membership.status = Status.Cancelled;

        tfiFarming.unstake(membership.lpAmount);
        lpToken.safeApprove(address(uniV2Router), membership.lpAmount);
        (uint256 tfiTokenOut, uint256 pairTokenOut) = uniV2Router.removeLiquidity(
            address(tfiToken),
            address(pairToken),
            membership.lpAmount,
            tfiMinOut,
            pairTokenMinOut,
            address(this),
            deadline
        );

        tfiToken.safeTransfer(owner(), tfiTokenOut);
        pairToken.safeTransfer(membership.pOwner, pairTokenOut);

        uint256 spent = membership.startTime > block.timestamp ? 0 : block.timestamp - membership.startTime;

        uint256 pTokenPaid = membership.pTokenAmount * spent / membership.period;

        IERC20(membership.pToken).safeTransfer(owner(), pTokenPaid);
        IERC20(membership.pToken).safeTransfer(membership.pOwner, membership.pTokenAmount - pTokenPaid);

        emit Cancelled(id, tfiTokenOut, pairTokenOut, pTokenPaid);
    }
}
