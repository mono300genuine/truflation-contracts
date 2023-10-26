// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/TfiPartner.sol";
import "../src/staking/StakingRewards.sol";
import "../src/libraries/Errors.sol";
import "./mock/MockERC20.sol";
import "./interfaces/IUniswapV2Factory.sol";

contract TfiPartnerTest is Test {
    TfiPartner public tfiPartner;

    address public alice;
    address public bob;
    address public gov;
    MockERC20 public pToken;
    MockERC20 public usdtToken;
    MockERC20 public tfiToken;
    IERC20 public lpToken;
    StakingRewards public lpStaking;
    IUniswapV2Router01 public uniswapRouter = IUniswapV2Router01(address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D));
    IUniswapV2Factory public uniswapFactory = IUniswapV2Factory(uniswapRouter.factory());

    bytes32 public partnerId = keccak256(abi.encode("Test Partner"));
    uint256 public period = 86400 * 365; // 1 year
    uint256 public startTime;
    uint256 public pTokenAmount = 10000e18;
    address public pOwner;
    uint256 public tfiAmount = 1000e18;
    uint256 public usdtTokenMaxIn = 4e9;
    uint256 public lpTokenMinOut = 1;
    uint256 public lpReward = 100e18;

    function setUp() public {
        pToken = new MockERC20(18);
        usdtToken = new MockERC20(6);
        tfiToken = new MockERC20(18);

        alice = address(uint160(uint256(keccak256(abi.encodePacked("Alice")))));
        bob = address(uint160(uint256(keccak256(abi.encodePacked("Bob")))));
        gov = address(uint160(uint256(keccak256(abi.encodePacked("Truflation Gov")))));
        pOwner = address(uint160(uint256(keccak256(abi.encodePacked("Protocol owner")))));
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(gov, "Truflation Gov");
        vm.label(pOwner, "Protocol owner");

        usdtToken.mint(address(this), 1e12); // mint 1,000,000 USDT
        tfiToken.mint(address(this), 3e23); // mint 300,000 TFI
        usdtToken.approve(address(uniswapRouter), 1e12);
        tfiToken.approve(address(uniswapRouter), 3e23);

        uniswapRouter.addLiquidity(
            address(tfiToken), address(usdtToken), 3e23, 1e12, 0, 0, address(this), block.timestamp
        );

        lpToken = IERC20(uniswapFactory.getPair(address(tfiToken), address(usdtToken)));
        lpStaking = new StakingRewards(
            address(this),
            address(tfiToken),
            address(lpToken)
        );

        tfiPartner = new TfiPartner(
            address(tfiToken),
            address(usdtToken),
            address(lpToken),
            address(lpStaking),
            address(uniswapRouter)
        );
        tfiPartner.transferOwnership(gov);

        tfiToken.mint(address(lpStaking), lpReward);
        lpStaking.notifyRewardAmount(lpReward);
    }

    function testConstructorSuccess() external {
        console.log("Check initial variables");
        assertEq(address(tfiPartner.tfiToken()), address(tfiToken), "Tfi token is invalid");
        assertEq(address(tfiPartner.pairToken()), address(usdtToken), "Pair token is invalid");
        assertEq(address(tfiPartner.lpToken()), address(lpToken), "Lp token is invalid");
        assertEq(address(tfiPartner.lpStaking()), address(lpStaking), "LP staking is invalid");
    }

    function testConstructorFailure() external {
        console.log("Should revert if tfiToken is address(0)");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new TfiPartner(
            address(0),
            address(usdtToken),
            address(lpToken),
            address(lpStaking),
            address(uniswapRouter)
        );

        console.log("Should revert if pairToken is address(0)");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new TfiPartner(
            address(tfiToken),
            address(0),
            address(lpToken),
            address(lpStaking),
            address(uniswapRouter)
        );

        console.log("Should revert if lpToken is address(0)");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new TfiPartner(
            address(tfiToken),
            address(usdtToken),
            address(0),
            address(lpStaking),
            address(uniswapRouter)
        );

        console.log("Should revert if lpToken is address(0)");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new TfiPartner(
            address(tfiToken),
            address(usdtToken),
            address(lpToken),
            address(0),
            address(uniswapRouter)
        );

        console.log("Should revert if uni v2 router is address(0)");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new TfiPartner(
            address(tfiToken),
            address(usdtToken),
            address(lpToken),
            address(lpStaking),
            address(0)
        );
    }

    function testInitiateSuccess() external {
        console.log("Should initiate partner information");
        _initiate();

        assertEq(tfiToken.balanceOf(address(tfiPartner)), tfiAmount, "TFI should be locked");
        (
            uint256 _period,
            uint256 _startTime,
            address _pToken,
            uint256 _pTokenAmount,
            address _pOwner,
            uint256 _tfiAmount,
            uint256 _lpAmount,
            uint256 _tfiRewardDebt,
            TfiPartner.Status _status
        ) = tfiPartner.subscriptions(partnerId);

        assertEq(_period, period, "Subscription period is not equal");
        assertEq(_startTime, startTime, "Subscription startTime is not equal");
        assertEq(_pToken, address(pToken), "Subscription pToken is not equal");
        assertEq(_pTokenAmount, pTokenAmount, "Subscription pTokenAmount is not equal");
        assertEq(_pOwner, pOwner, "Subscription pOwner is not equal");
        assertEq(_tfiAmount, tfiAmount, "Subscription tfiAmount is not equal");
        assertEq(_lpAmount, 0, "Subscription lpAmount should be zero");
        assertEq(_tfiRewardDebt, 0, "Subscription debt should be zero");
        assertEq(_status == TfiPartner.Status.Initiated, true, "Subscription status should be Initiated");
    }

    function testInitiateFailureIfSenderIsNotGov() external {
        console.log("Should revert if msg.sender is not gov");
        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        tfiPartner.initiate(partnerId, period, startTime, address(pToken), pTokenAmount, pOwner, tfiAmount);
        vm.stopPrank();
    }

    function testInitiateFailureIfPeriodIsZero() external {
        tfiToken.mint(gov, tfiAmount * 2);
        startTime = block.timestamp + 86400;

        vm.startPrank(gov);

        tfiToken.approve(address(tfiPartner), tfiAmount * 2);

        console.log("Should revert if period is 0");
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        tfiPartner.initiate(partnerId, 0, startTime, address(pToken), pTokenAmount, pOwner, tfiAmount);

        vm.stopPrank();
    }

    function testInitiateFailureIfPTokenAmountIsZero() external {
        tfiToken.mint(gov, tfiAmount * 2);
        startTime = block.timestamp + 86400;

        vm.startPrank(gov);

        tfiToken.approve(address(tfiPartner), tfiAmount * 2);

        console.log("Should revert if pTokenAmount is 0");
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        tfiPartner.initiate(partnerId, period, startTime, address(pToken), 0, pOwner, tfiAmount);

        vm.stopPrank();
    }

    function testInitiateFailureIfTfiAmountIsZero() external {
        tfiToken.mint(gov, tfiAmount * 2);
        startTime = block.timestamp + 86400;

        vm.startPrank(gov);

        tfiToken.approve(address(tfiPartner), tfiAmount * 2);

        console.log("Should revert if tfiAmount is 0");
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        tfiPartner.initiate(partnerId, period, startTime, address(pToken), pTokenAmount, pOwner, 0);

        vm.stopPrank();
    }

    function testInitiateFailureIfStartTimeIsLowerThanCurrentTime() external {
        tfiToken.mint(gov, tfiAmount * 2);
        startTime = block.timestamp + 86400;

        vm.startPrank(gov);

        tfiToken.approve(address(tfiPartner), tfiAmount * 2);

        console.log("Should revert if startTime is lower than current timestamp");
        vm.expectRevert(abi.encodeWithSignature("InvalidTimestamp()"));
        tfiPartner.initiate(partnerId, period, block.timestamp - 1, address(pToken), pTokenAmount, pOwner, tfiAmount);

        vm.stopPrank();
    }

    function testInitiateFailureIfPTokenIsZero() external {
        tfiToken.mint(gov, tfiAmount * 2);
        startTime = block.timestamp + 86400;

        vm.startPrank(gov);

        tfiToken.approve(address(tfiPartner), tfiAmount * 2);

        console.log("Should revert if pToken is address(0)");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        tfiPartner.initiate(partnerId, period, startTime, address(0), pTokenAmount, pOwner, tfiAmount);

        vm.stopPrank();
    }

    function testInitiateFailureIfPOwnerIsZero() external {
        tfiToken.mint(gov, tfiAmount * 2);
        startTime = block.timestamp + 86400;

        vm.startPrank(gov);

        tfiToken.approve(address(tfiPartner), tfiAmount * 2);

        console.log("Should revert if pOwner is address(0)");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        tfiPartner.initiate(partnerId, period, startTime, address(pToken), pTokenAmount, address(0), tfiAmount);

        vm.stopPrank();
    }

    function testInitiateFailureIfSubscriptionStatusIsNotNone() external {
        tfiToken.mint(gov, tfiAmount * 2);
        startTime = block.timestamp + 86400;

        vm.startPrank(gov);

        tfiToken.approve(address(tfiPartner), tfiAmount * 2);

        console.log("Should revert if subscription status is not None");
        tfiPartner.initiate(partnerId, period, startTime, address(pToken), pTokenAmount, pOwner, tfiAmount);
        vm.expectRevert(abi.encodeWithSignature("InvalidStatus(bytes32)", partnerId));
        tfiPartner.initiate(partnerId, period, startTime, address(pToken), pTokenAmount, pOwner, tfiAmount);

        vm.stopPrank();
    }

    function testPaySuccess() external {
        uint256 initialLp = lpToken.totalSupply();
        console.log("Should pay protocol token and add liquidity");
        _initiate();

        uint256 usdtBalance = usdtToken.balanceOf(pOwner);
        _pay();

        uint256 lpAmount = lpToken.totalSupply() - initialLp;
        assertEq(lpAmount > 0, true, "LP amount must be greater than zero");

        assertEq(pToken.balanceOf(address(tfiPartner)), pTokenAmount, "pToken should be locked");
        assertEq(tfiToken.balanceOf(address(tfiPartner)), 0, "TFI should be added as liquidity");
        (
            uint256 _period,
            uint256 _startTime,
            address _pToken,
            uint256 _pTokenAmount,
            address _pOwner,
            uint256 _tfiAmount,
            uint256 _lpAmount,
            uint256 _tfiRewardDebt,
            TfiPartner.Status _status
        ) = tfiPartner.subscriptions(partnerId);

        assertEq(_period, period, "Subscription period is not equal");
        assertEq(_startTime, startTime, "Subscription startTime is not equal");
        assertEq(_pToken, address(pToken), "Subscription pToken is not equal");
        assertEq(_pTokenAmount, pTokenAmount, "Subscription pTokenAmount is not equal");
        assertEq(_pOwner, pOwner, "Subscription pOwner is not equal");
        assertEq(_tfiAmount, tfiAmount, "Subscription tfiAmount is not equal");
        assertEq(_lpAmount, lpAmount, "Subscription lpAmount is not equal");
        assertEq(_tfiRewardDebt, 0, "Subscription tfiRewardDebt is not equal");
        assertEq(_status == TfiPartner.Status.Active, true, "Subscription status should be Active");
        assertEq(usdtToken.balanceOf(pOwner) > usdtBalance, true, "Should received remain USDT");
        assertEq(usdtToken.balanceOf(address(tfiPartner)), 0, "USDT balance of contract should be zero");
        assertEq(lpStaking.balanceOf(address(tfiPartner)), lpAmount, "LP should be staked");
        assertEq(lpToken.balanceOf(address(tfiPartner)), 0, "LP balance of contract should be zero after staked");
        assertEq(tfiPartner.totalLpStaked(), lpAmount, "Liquidity should be staked");
    }

    function testPayFailureIfSenderIsNotProtocolOwner() external {
        _initiate();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("Forbidden(address)", alice));
        tfiPartner.pay(partnerId, usdtTokenMaxIn, 1, block.timestamp);
        vm.stopPrank();
    }

    function testPayFailureIfStatusIsIncorrect() external {
        _initiate();
        _pay();

        vm.startPrank(pOwner);
        vm.expectRevert(abi.encodeWithSignature("InvalidStatus(bytes32)", partnerId));
        tfiPartner.pay(partnerId, usdtTokenMaxIn, 1, block.timestamp);
        vm.stopPrank();
    }

    function testPayFailureIfAlreadyStarted() external {
        _initiate();

        vm.warp(block.timestamp + 86500);
        vm.startPrank(pOwner);
        vm.expectRevert(abi.encodeWithSignature("InvalidTimestamp()"));
        tfiPartner.pay(partnerId, usdtTokenMaxIn, 1, block.timestamp);
        vm.stopPrank();
    }

    function testEndSuccess() external {
        uint256 initialLp = lpToken.totalSupply();
        _initiate();

        _pay();
        uint256 usdtBalance = usdtToken.balanceOf(pOwner);

        uint256 lpAmount = lpToken.totalSupply() - initialLp;

        vm.warp(block.timestamp + period + 86500);

        _end();

        assertEq(pToken.balanceOf(address(tfiPartner)), 0, "pToken should be unlocked");
        assertEq(pToken.balanceOf(gov), pTokenAmount, "pToken should be sent to gov");
        assertEq(tfiToken.balanceOf(address(tfiPartner)) < 10, true, "TFI should be unlocked");

        assertEq(tfiToken.balanceOf(pOwner) > 0, true, "TFI should be sent to pOwner");
        (
            uint256 _period,
            uint256 _startTime,
            address _pToken,
            uint256 _pTokenAmount,
            address _pOwner,
            uint256 _tfiAmount,
            uint256 _lpAmount,
            uint256 _tfiRewardDebt,
            TfiPartner.Status _status
        ) = tfiPartner.subscriptions(partnerId);

        assertEq(_period, period, "Subscription period is not equal");
        assertEq(_startTime, startTime, "Subscription startTime is not equal");
        assertEq(_pToken, address(pToken), "Subscription pToken is not equal");
        assertEq(_pTokenAmount, pTokenAmount, "Subscription pTokenAmount is not equal");
        assertEq(_pOwner, pOwner, "Subscription pOwner is not equal");
        assertEq(_tfiAmount, tfiAmount, "Subscription tfiAmount is not equal");
        assertEq(_lpAmount, lpAmount, "Subscription lpAmount is not equal");
        assertEq(_tfiRewardDebt, 0, "Subscription tfiRewardDebt is not equal");
        assertEq(_status == TfiPartner.Status.Ended, true, "Subscription status should be Ended");
        assertEq(usdtToken.balanceOf(pOwner) > usdtBalance, true, "USDT should be unlocked and sent to pOwner");
        assertEq(usdtToken.balanceOf(address(tfiPartner)), 0, "USDT balance of contract should be zero");
        assertEq(lpStaking.balanceOf(address(tfiPartner)), 0, "LP should be unstaked");
        assertEq(lpToken.totalSupply(), initialLp, "Liquidity should be removed");
        assertEq(tfiPartner.totalLpStaked(), 0, "Liquidity should be removed");
    }

    function testEndFailureIfSenderIsNotGov() external {
        _initiate();
        _pay();

        vm.warp(block.timestamp + period + 86500);

        console.log("Should revert if msg.sender is not gov");
        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        tfiPartner.end(partnerId, 1, 1, block.timestamp);
        vm.stopPrank();
    }

    function testCancelSuccessWhenInitiated() external {
        _initiate();

        vm.warp(startTime + period / 3);

        _cancel();

        assertEq(tfiToken.balanceOf(address(tfiPartner)) == 0, true, "TFI should be unlocked");
        assertEq(tfiToken.balanceOf(gov), tfiAmount, "TFI should be sent to gov");
        (
            uint256 _period,
            uint256 _startTime,
            address _pToken,
            uint256 _pTokenAmount,
            address _pOwner,
            uint256 _tfiAmount,
            uint256 _lpAmount,
            uint256 _tfiRewardDebt,
            TfiPartner.Status _status
        ) = tfiPartner.subscriptions(partnerId);

        assertEq(_period, 0, "Subscription period should be deleted");
        assertEq(_startTime, 0, "Subscription startTime should be deleted");
        assertEq(_pToken, address(0), "Subscription pToken should be deleted");
        assertEq(_pTokenAmount, 0, "Subscription pTokenAmount should be deleted");
        assertEq(_pOwner, address(0), "Subscription pOwner should be deleted");
        assertEq(_tfiAmount, 0, "Subscription tfiAmount should be deleted");
        assertEq(_lpAmount, 0, "Subscription lpAmount should be deleted");
        assertEq(_tfiRewardDebt, 0, "Subscription tfiRewardDebt should be deleted");
        assertEq(_status == TfiPartner.Status.None, true, "Subscription status should be None");
    }

    function testCancelSuccessWhenActive() external {
        uint256 initialLp = lpToken.totalSupply();
        _initiate();

        _pay();
        uint256 usdtBalance = usdtToken.balanceOf(pOwner);

        uint256 lpAmount = lpToken.totalSupply() - initialLp;

        vm.warp(startTime + period / 3);

        _cancel();

        assertEq(pToken.balanceOf(address(tfiPartner)), 0, "pToken should be unlocked");
        assertEq(pToken.balanceOf(pOwner), pTokenAmount - (pTokenAmount / 3), "Some of pToken should be sent to pOwner");
        assertEq(pToken.balanceOf(gov), pTokenAmount / 3, "Some of pToken should be sent to gov");
        assertEq(tfiToken.balanceOf(address(tfiPartner)) < 10, true, "TFI should be unlocked");
        assertEq(tfiToken.balanceOf(pOwner) == 0, true, "TFI should not be sent to pOwner");
        assertEq(tfiToken.balanceOf(gov) > 0, true, "TFI should be sent to gov");
        (
            uint256 _period,
            uint256 _startTime,
            address _pToken,
            uint256 _pTokenAmount,
            address _pOwner,
            uint256 _tfiAmount,
            uint256 _lpAmount,
            uint256 _tfiRewardDebt,
            TfiPartner.Status _status
        ) = tfiPartner.subscriptions(partnerId);

        assertEq(_period, period, "Subscription period is not equal");
        assertEq(_startTime, startTime, "Subscription startTime is not equal");
        assertEq(_pToken, address(pToken), "Subscription pToken is not equal");
        assertEq(_pTokenAmount, pTokenAmount, "Subscription pTokenAmount is not equal");
        assertEq(_pOwner, pOwner, "Subscription pOwner is not equal");
        assertEq(_tfiAmount, tfiAmount, "Subscription tfiAmount is not equal");
        assertEq(_lpAmount, lpAmount, "Subscription lpAmount is not equal");
        assertEq(_tfiRewardDebt, 0, "Subscription tfiRewardDebt is not equal");
        assertEq(_status == TfiPartner.Status.Cancelled, true, "Subscription status should be Cancelled");
        assertEq(usdtToken.balanceOf(pOwner) > usdtBalance, true, "USDT should be unlocked and sent to pOwner");
        assertEq(usdtToken.balanceOf(address(tfiPartner)), 0, "USDT balance of contract should be zero");
        assertEq(lpStaking.balanceOf(address(tfiPartner)), 0, "LP should be unstaked");
        assertEq(lpToken.totalSupply(), initialLp, "Liquidity should be removed");
        assertEq(tfiPartner.totalLpStaked(), 0, "Liquidity should be removed");
    }

    function testCancelFailureIfSenderIsNotGov() external {
        _initiate();
        _pay();

        vm.warp(startTime + period / 3);

        console.log("Should revert if msg.sender is not gov");
        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        tfiPartner.cancel(partnerId, 1, 1, block.timestamp);
        vm.stopPrank();
    }

    function testCancelFailureIfStatusIsIncorrect() external {
        vm.warp(startTime + period / 3);

        console.log("Should revert if status is not Initated Or Active");
        vm.startPrank(gov);
        vm.expectRevert(abi.encodeWithSignature("InvalidStatus(bytes32)", partnerId));
        tfiPartner.cancel(partnerId, 1, 1, block.timestamp);
        vm.stopPrank();
    }

    function testCancelFailureBeforeStartTimeWhenStatusIsInitiated() external {
        _initiate();
        vm.warp(startTime - 10);

        console.log("Should revert if status is Initiated and current time is lower than start time");
        vm.startPrank(gov);
        vm.expectRevert(abi.encodeWithSignature("InvalidTimestamp()"));
        tfiPartner.cancel(partnerId, 1, 1, block.timestamp);
        vm.stopPrank();
    }

    function testCancelFailureAfterMaturity() external {
        _initiate();
        _pay();

        vm.warp(startTime + period + 1);

        console.log("Should revert if maturity was not elapsed yet");
        vm.startPrank(gov);
        vm.expectRevert(abi.encodeWithSignature("InvalidTimestamp()"));
        tfiPartner.cancel(partnerId, 1, 1, block.timestamp);
        vm.stopPrank();
    }

    function _initiate() internal {
        tfiToken.mint(gov, tfiAmount);

        vm.startPrank(gov);
        startTime = block.timestamp + 86400;
        tfiToken.approve(address(tfiPartner), tfiAmount);
        tfiPartner.initiate(partnerId, period, startTime, address(pToken), pTokenAmount, pOwner, tfiAmount);
        vm.stopPrank();
    }

    function _pay() internal {
        pToken.mint(pOwner, pTokenAmount);
        usdtToken.mint(pOwner, usdtTokenMaxIn);

        vm.startPrank(pOwner);
        startTime = block.timestamp + 86400;
        pToken.approve(address(tfiPartner), pTokenAmount);
        usdtToken.approve(address(tfiPartner), usdtTokenMaxIn);
        tfiPartner.pay(partnerId, usdtTokenMaxIn, lpTokenMinOut, block.timestamp);
        vm.stopPrank();
    }

    function _end() internal {
        vm.startPrank(gov);
        tfiPartner.end(partnerId, 1, 1, block.timestamp);
        vm.stopPrank();
    }

    function _cancel() internal {
        vm.startPrank(gov);
        tfiPartner.cancel(partnerId, 1, 1, block.timestamp);
        vm.stopPrank();
    }
}
