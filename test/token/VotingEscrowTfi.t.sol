// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import {PRBMathUD60x18} from "paulrberg/prb-math/contracts/PRBMathUD60x18.sol";
import "../../src/token/TruflationToken.sol";
import "../../src/token/TfiVesting.sol";
import "../../src/token/VotingEscrowTfi.sol";
import "../../src/staking/VirtualStakingRewards.sol";

contract VotingEscrowTfiTest is Test {
    event Stake(
        address indexed user, bool indexed isVesting, uint256 lockupId, uint256 amount, uint256 end, uint256 points
    );
    event Unstake(
        address indexed user, bool indexed isVesting, uint256 lockupId, uint256 amount, uint256 end, uint256 points
    );
    event Migrated(address indexed oldUser, address indexed newUser, uint256 oldLockupId, uint256 newLockupId);
    event Cancelled(address indexed user, uint256 lockupId, uint256 amount, uint256 points);

    TruflationToken public tfiToken;
    VotingEscrowTfi public veTFI;
    VirtualStakingRewards public tfiStakingRewards;

    // Config
    string public name = "Voting Escrowed TFI";
    string public symbol = "veTFI";

    uint256 public minStakeDuration = 1 hours;
    uint256 public epoch;
    uint256 public constant YEAR_BASE = 18e17;

    // Users
    address public alice;
    address public bob;
    address public carol;
    address public owner;
    address public vesting;

    function setUp() public {
        alice = address(uint160(uint256(keccak256(abi.encodePacked("Alice")))));
        bob = address(uint160(uint256(keccak256(abi.encodePacked("Bob")))));
        carol = address(uint160(uint256(keccak256(abi.encodePacked("Carol")))));
        owner = address(uint160(uint256(keccak256(abi.encodePacked("Owner")))));
        vesting = address(uint160(uint256(keccak256(abi.encodePacked("Vesting")))));

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(carol, "Carol");
        vm.label(vesting, "Vesting");

        vm.warp(1696816730);

        epoch = block.timestamp + 1 days;

        vm.startPrank(owner);
        tfiToken = new TruflationToken();
        tfiToken.transfer(alice, tfiToken.totalSupply() / 3);
        tfiToken.transfer(vesting, tfiToken.totalSupply() / 3);
        tfiStakingRewards = new VirtualStakingRewards(owner, address(tfiToken));
        veTFI =
        new VotingEscrowTfi(address(tfiToken), address(vesting), epoch, minStakeDuration, address(tfiStakingRewards));
        tfiStakingRewards.setOperator(address(veTFI));
        tfiToken.transfer(address(tfiStakingRewards), 200e18);
        tfiStakingRewards.notifyRewardAmount(200e18);

        vm.stopPrank();

        vm.startPrank(alice);
        tfiToken.approve(address(veTFI), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(vesting);
        tfiToken.approve(address(veTFI), type(uint256).max);
        vm.stopPrank();
    }

    function testConstructorSuccess() external {
        console.log("Check initial variables");
        assertEq(address(veTFI.tfiToken()), address(tfiToken), "Tfi Token is invalid");
        assertEq(veTFI.tfiVesting(), vesting, "Vesting is invalid");
        assertEq(veTFI.epoch(), epoch, "Epoch is invalid");
        assertEq(veTFI.minStakeDuration(), minStakeDuration, "minStakeDuration is invalid");
        assertEq(address(veTFI.stakingRewards()), address(tfiStakingRewards), "StakingRewards is invalid");
        assertEq(veTFI.name(), name, "Name is invalid");
        assertEq(veTFI.symbol(), symbol, "Symbol is invalid");
        assertEq(veTFI.decimals(), 18, "Decimal is invalid");
    }

    function testTransfer_RevertAnytmie() external {
        console.log("Always revert when transfering token");

        _stake(100e18, 30 days, alice, alice);

        assertNotEq(veTFI.balanceOf(alice), 0, "Alice does not have veTFI");

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("TransferDisabled()"));
        veTFI.transfer(bob, 1);

        vm.stopPrank();
    }

    function testStake_FirstTime() external {
        console.log("Stake first time");

        uint256 amount = 100e18;
        uint256 duration = 30 days;

        (uint256 points, uint256 ends) = veTFI.previewPoints(amount, duration);
        assertNotEq(points, 0, "Points should be non-zero");

        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true, address(veTFI));
        emit Stake(bob, false, 0, amount, ends, points);

        veTFI.stake(amount, duration, bob);

        vm.stopPrank();

        assertEq(veTFI.balanceOf(alice), 0, "Alice should not have balance");
        assertEq(veTFI.balanceOf(bob), points, "Bob should have balance");
        assertEq(tfiStakingRewards.balanceOf(bob), points, "Bob should have staking balance");
        assertEq(tfiToken.balanceOf(address(veTFI)), amount, "TFI token should be transferred");
        assertEq(veTFI.delegates(bob), bob, "Delegate is invalid");

        _validateLockup(bob, 0, amount, ends, points, false);
    }

    function testStake_SecondTime() external {
        console.log("Stake second time");

        _stake(100e18, 30 days, alice, bob);

        uint256 amount = 1000e18;
        uint256 duration = 60 days;

        uint256 prevBalance = veTFI.balanceOf(bob);

        (uint256 points, uint256 ends) = veTFI.previewPoints(amount, duration);
        assertNotEq(points, 0, "Points should be non-zero");

        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true, address(veTFI));
        emit Stake(bob, false, 1, amount, ends, points);

        veTFI.stake(amount, duration, bob);

        vm.stopPrank();

        assertEq(veTFI.balanceOf(bob), prevBalance + points, "Bob should have balance");
        assertEq(tfiStakingRewards.balanceOf(bob), prevBalance + points, "Bob should have staking balance");
        assertEq(tfiToken.balanceOf(address(veTFI)), amount + 100e18, "TFI token should be transferred");
        assertEq(veTFI.delegates(bob), bob, "Delegate is invalid");

        _validateLockup(bob, 1, amount, ends, points, false);
    }

    function testStake_DoNotChangeDelegateeIfAlreadySet() external {
        console.log("Do not change delegatee if already set");

        vm.startPrank(alice);

        veTFI.delegate(bob);

        vm.stopPrank();

        _stake(100e18, 30 days, alice, alice);

        assertEq(veTFI.delegates(alice), bob, "Delegate is invalid");
    }

    function testStakeFailure() external {
        vm.startPrank(alice);

        console.log("Revert if amount is 0");
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        veTFI.stake(0, 30 days, bob);

        console.log("Revert if to is address(0)");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        veTFI.stake(100e18, 30 days, address(0));

        console.log("Revert if amount is greater than uint128.max");
        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        veTFI.stake(uint256(type(uint128).max) + 1, 30 days, bob);

        vm.stopPrank();
    }

    function testStakeVesting() external {
        console.log("Stake vesting");

        uint256 amount = 100e18;
        uint256 duration = 30 days;

        (uint256 points, uint256 ends) = veTFI.previewPoints(amount, duration);
        assertNotEq(points, 0, "Points should be non-zero");

        vm.startPrank(vesting);

        vm.expectEmit(true, true, true, true, address(veTFI));
        emit Stake(bob, true, 0, amount, ends, points);

        assertEq(veTFI.stakeVesting(amount, duration, bob), 0, "Lockup id is invalid");

        vm.stopPrank();

        assertEq(veTFI.balanceOf(alice), 0, "Alice should not have balance");
        assertEq(veTFI.balanceOf(bob), points, "Bob should have balance");
        assertEq(tfiStakingRewards.balanceOf(bob), points, "Bob should have staking balance");
        assertEq(tfiToken.balanceOf(address(veTFI)), amount, "TFI token should be transferred");
        assertEq(veTFI.delegates(bob), bob, "Delegate is invalid");

        _validateLockup(bob, 0, amount, ends, points, true);
    }

    function testStakeVestingFailure() external {
        vm.startPrank(alice);

        console.log("Revert if msg.sender is not vesting");
        vm.expectRevert(abi.encodeWithSignature("Forbidden(address)", alice));
        veTFI.stakeVesting(100e18, 30 days, vesting);

        vm.stopPrank();

        vm.startPrank(vesting);

        console.log("Revert if to is vesting");
        vm.expectRevert(abi.encodeWithSignature("InvalidAccount()"));
        veTFI.stakeVesting(100e18, 30 days, vesting);

        vm.stopPrank();
    }

    function testUnstake() external {
        console.log("Unstake lockup");

        uint256 amount = 100e18;
        uint256 duration = 30 days;

        _stake(amount, duration, alice, bob);

        (uint256 points, uint256 ends) = veTFI.previewPoints(amount, duration);
        assertNotEq(points, 0, "Points should be non-zero");

        vm.warp(ends);

        vm.startPrank(bob);

        vm.expectEmit(true, true, true, true, address(veTFI));
        emit Unstake(bob, false, 0, amount, ends, points);

        veTFI.unstake(0);

        vm.stopPrank();

        assertEq(veTFI.balanceOf(bob), 0, "Bob should have no balance");
        assertEq(tfiStakingRewards.balanceOf(bob), 0, "Bob should have no staking balance");
        assertEq(tfiToken.balanceOf(address(veTFI)), 0, "TFI token should be transferred from veTFI");
        assertEq(tfiToken.balanceOf(bob), amount, "TFI token should be transferred to bob");

        _validateLockup(bob, 0, 0, 0, 0, false);
    }

    function testUnstakeFailures() external {
        uint256 amount = 100e18;
        uint256 duration = 30 days;

        _stake(amount, duration, alice, bob);

        (uint256 points, uint256 ends) = veTFI.previewPoints(amount, duration);
        assertNotEq(points, 0, "Points should be non-zero");

        console.log("Revert to unstake if trying to unstake as vesting");

        vm.startPrank(vesting);

        vm.expectRevert(abi.encodeWithSignature("NoAccess()"));
        veTFI.unstakeVesting(bob, 0, false);

        vm.stopPrank();

        vm.startPrank(bob);

        console.log("Revert to unstake if lockup period not ended");

        vm.warp(block.timestamp + 10 days);
        vm.expectRevert(abi.encodeWithSignature("LockupNotEnded()"));
        veTFI.unstake(0);

        console.log("Revert to unstake if already unstaked");

        vm.warp(ends);
        veTFI.unstake(0);

        vm.expectRevert(abi.encodeWithSignature("LockupAlreadyUnstaked()"));
        veTFI.unstake(0);

        vm.stopPrank();
    }

    function testUnstakeVesting_NotForce() external {
        console.log("Unstake vesting lockup");

        uint256 amount = 100e18;
        uint256 duration = 30 days;

        _stakeVesting(amount, duration, bob);

        uint256 prevVestingBal = tfiToken.balanceOf(vesting);

        (uint256 points, uint256 ends) = veTFI.previewPoints(amount, duration);
        assertNotEq(points, 0, "Points should be non-zero");

        vm.warp(ends);

        vm.startPrank(vesting);

        vm.expectEmit(true, true, true, true, address(veTFI));
        emit Unstake(bob, true, 0, amount, ends, points);

        veTFI.unstakeVesting(bob, 0, false);

        vm.stopPrank();

        assertEq(veTFI.balanceOf(bob), 0, "Bob should have no balance");
        assertEq(tfiStakingRewards.balanceOf(bob), 0, "Bob should have no staking balance");
        assertEq(tfiToken.balanceOf(address(veTFI)), 0, "TFI token should be transferred from veTFI");
        assertEq(tfiToken.balanceOf(vesting), prevVestingBal + amount, "TFI token should be transferred to vesting");

        _validateLockup(bob, 0, 0, 0, 0, false);
    }

    function testUnstakeVesting_Force() external {
        console.log("Unstake vesting lockup forcefully before ends");

        uint256 amount = 100e18;
        uint256 duration = 30 days;

        _stakeVesting(amount, duration, bob);

        uint256 prevVestingBal = tfiToken.balanceOf(vesting);

        (uint256 points, uint256 ends) = veTFI.previewPoints(amount, duration);
        assertNotEq(points, 0, "Points should be non-zero");

        vm.warp(block.timestamp + 10 days);

        vm.startPrank(vesting);

        vm.expectEmit(true, true, true, true, address(veTFI));
        emit Cancelled(bob, 0, amount, points);

        veTFI.unstakeVesting(bob, 0, true);

        vm.stopPrank();

        assertEq(veTFI.balanceOf(bob), 0, "Bob should have no balance");
        assertEq(tfiStakingRewards.balanceOf(bob), 0, "Bob should have no staking balance");
        assertEq(tfiToken.balanceOf(address(veTFI)), 0, "TFI token should be transferred from veTFI");
        assertEq(tfiToken.balanceOf(vesting), prevVestingBal + amount, "TFI token should be transferred to vesting");

        _validateLockup(bob, 0, 0, 0, 0, false);
    }

    function testUnstakeVestingFailures() external {
        uint256 amount = 100e18;
        uint256 duration = 30 days;

        _stakeVesting(amount, duration, bob);

        console.log("Revert to unstake if trying to unstake as normal");

        vm.startPrank(bob);

        vm.expectRevert(abi.encodeWithSignature("NoAccess()"));
        veTFI.unstake(0);

        console.log("Revert if msg.sender is not vesting");
        vm.expectRevert(abi.encodeWithSignature("Forbidden(address)", bob));
        veTFI.unstakeVesting(bob, 0, false);

        vm.stopPrank();
    }

    function testIncreaseLock() external {
        console.log("Increase amount or duration of lockup");

        uint256 amount = 100e18;
        uint256 duration = 30 days;

        _stake(amount, duration, alice, alice);

        vm.warp(block.timestamp + 10 days);

        uint256 increaseAmount = 1000e18;
        uint256 increaseDuration = 60 days;

        (uint256 newPoints, uint256 newEnds) = veTFI.previewPoints(amount + increaseAmount, increaseDuration);
        assertNotEq(newPoints, 0, "Points should be non-zero");

        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true, address(veTFI));
        emit Stake(alice, false, 0, amount + increaseAmount, newEnds, newPoints);

        veTFI.increaseLock(0, increaseAmount, increaseDuration);

        vm.stopPrank();

        assertEq(veTFI.balanceOf(alice), newPoints, "Mint increased points to alice");
        assertEq(tfiStakingRewards.balanceOf(alice), newPoints, "Stake increased points to staking rewards");
        assertEq(
            tfiToken.balanceOf(address(veTFI)), amount + increaseAmount, "Increased amount should be sent to veTFI"
        );

        _validateLockup(alice, 0, amount + increaseAmount, newEnds, newPoints, false);
    }

    function testIncreaseLock_IncreaseWithZeroAmount() external {
        console.log("Increase without amount");

        uint256 amount = 100e18;
        uint256 duration = 30 days;

        _stake(amount, duration, alice, alice);

        vm.warp(block.timestamp + 10 days);

        uint256 increaseDuration = 60 days;

        (uint256 newPoints, uint256 newEnds) = veTFI.previewPoints(amount, increaseDuration);
        assertNotEq(newPoints, 0, "Points should be non-zero");

        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true, address(veTFI));
        emit Stake(alice, false, 0, amount, newEnds, newPoints);

        veTFI.increaseLock(0, 0, increaseDuration);

        vm.stopPrank();

        assertEq(veTFI.balanceOf(alice), newPoints, "Mint increased points to alice");
        assertEq(tfiStakingRewards.balanceOf(alice), newPoints, "Stake increased points to staking rewards");
        assertEq(tfiToken.balanceOf(address(veTFI)), amount, "No amount transferred");

        _validateLockup(alice, 0, amount, newEnds, newPoints, false);
    }

    function testIncreaseLockFailures() external {
        uint256 amount = 100e18;
        uint256 duration = 30 days;

        _stake(amount, duration, alice, alice);

        (uint256 points,) = veTFI.previewPoints(amount, duration);
        assertNotEq(points, 0, "Points should be non-zero");

        uint256 increaseAmount = 1000e18;
        uint256 increaseDuration = 60 days;

        console.log("Revert to increase if trying to increase as vesting");

        vm.warp(block.timestamp + 10 days);

        vm.startPrank(vesting);

        vm.expectRevert(abi.encodeWithSignature("NoAccess()"));
        veTFI.increaseVestingLock(alice, 0, increaseAmount, increaseDuration);

        vm.stopPrank();

        vm.startPrank(alice);

        console.log("Revert to increase if new amount is greater than uint128.max");

        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        veTFI.increaseLock(0, type(uint128).max - amount + 1, increaseDuration);

        console.log("Revert to increase if new end is earlier than previous one");

        vm.expectRevert(abi.encodeWithSignature("NewDurationMustBeLonger()"));
        veTFI.increaseLock(0, increaseAmount, duration - 10 days);

        vm.stopPrank();
    }

    function testIncreaseVestingLock() external {
        console.log("Increase amount or duration of vesting lockup");

        uint256 amount = 100e18;
        uint256 duration = 30 days;

        _stakeVesting(amount, duration, alice);

        vm.warp(block.timestamp + 10 days);

        uint256 increaseAmount = 1000e18;
        uint256 increaseDuration = 60 days;

        (uint256 newPoints, uint256 newEnds) = veTFI.previewPoints(amount + increaseAmount, increaseDuration);
        assertNotEq(newPoints, 0, "Points should be non-zero");

        vm.startPrank(vesting);

        vm.expectEmit(true, true, true, true, address(veTFI));
        emit Stake(alice, true, 0, amount + increaseAmount, newEnds, newPoints);

        veTFI.increaseVestingLock(alice, 0, increaseAmount, increaseDuration);

        vm.stopPrank();

        assertEq(veTFI.balanceOf(alice), newPoints, "Mint increased points to alice");
        assertEq(tfiStakingRewards.balanceOf(alice), newPoints, "Stake increased points to staking rewards");
        assertEq(
            tfiToken.balanceOf(address(veTFI)), amount + increaseAmount, "Increased amount should be sent to veTFI"
        );

        _validateLockup(alice, 0, amount + increaseAmount, newEnds, newPoints, true);
    }

    function testIncreaseVestingLockFailures() external {
        uint256 amount = 100e18;
        uint256 duration = 30 days;

        _stakeVesting(amount, duration, alice);

        console.log("Revert to increase if trying to increase as normal");

        vm.warp(block.timestamp + 10 days);

        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSignature("NoAccess()"));
        veTFI.increaseLock(0, 10e18, duration);

        console.log("Revert if msg.sender is not vesting");
        vm.expectRevert(abi.encodeWithSignature("Forbidden(address)", alice));
        veTFI.increaseVestingLock(alice, 0, 10e18, duration);

        vm.stopPrank();
    }

    function testMigrateVestingLock() external {
        console.log("Migrate vesting lock to new user");

        uint256 amount = 100e18;
        uint256 duration = 30 days;

        uint256 aliceAmount = 50e18;
        uint256 aliceDuration = 20 days;

        _stake(aliceAmount, aliceDuration, alice, alice);
        _stakeVesting(amount, duration, alice);

        (uint256 alicePoints,) = veTFI.previewPoints(aliceAmount, aliceDuration);

        (uint256 points, uint256 ends) = veTFI.previewPoints(amount, duration);
        assertNotEq(points, 0, "Points should be non-zero");

        vm.startPrank(vesting);

        vm.expectEmit(true, true, true, true, address(veTFI));
        emit Migrated(alice, bob, 1, 0);

        veTFI.migrateVestingLock(alice, bob, 1);

        vm.stopPrank();

        assertEq(veTFI.balanceOf(alice), alicePoints, "Points should be burned");
        assertEq(tfiStakingRewards.balanceOf(alice), alicePoints, "Stake amount should be reduced");
        assertEq(veTFI.balanceOf(bob), points, "Points should be minted to new user");
        assertEq(tfiStakingRewards.balanceOf(bob), points, "Stake amount should be moved to new user");

        _validateLockup(alice, 1, 0, 0, 0, false);
        _validateLockup(bob, 0, amount, ends, points, true);
    }

    function testMigrateVestingLockFailures() external {
        _stakeVesting(100e18, 30 days, alice);
        _stake(100e18, 30 days, alice, alice);

        console.log("Revert if msg.sender is not vesting");
        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSignature("Forbidden(address)", alice));
        veTFI.migrateVestingLock(alice, bob, 0);

        vm.stopPrank();

        vm.startPrank(vesting);

        console.log("Revert if old user and new user is same");
        vm.expectRevert(abi.encodeWithSignature("NotMigrate()"));
        veTFI.migrateVestingLock(alice, alice, 0);

        console.log("Revert if new user is address(0)");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        veTFI.migrateVestingLock(alice, address(0), 0);

        console.log("Revert to migrate non-vesting lockup");
        vm.expectRevert(abi.encodeWithSignature("NoAccess()"));
        veTFI.migrateVestingLock(alice, bob, 1);

        vm.stopPrank();
    }

    function testClaimReward() external {
        console.log("Claim reward");

        uint256 amount = 100e18;
        uint256 duration = 30 days;

        _stake(amount, duration, alice, bob);

        vm.warp(block.timestamp + 10 days);

        uint256 earned = tfiStakingRewards.earned(bob);
        assertNotEq(earned, 0, "Earned reward should be non-zero");

        vm.startPrank(bob);

        veTFI.claimReward();

        vm.stopPrank();

        assertEq(tfiStakingRewards.earned(bob), 0, "Earned reward should be zero");
        assertEq(tfiToken.balanceOf(bob), earned, "Bob should receive reward");
    }

    function testPreviewPoints() external {
        console.log("Revert if duration is too short");
        vm.expectRevert(abi.encodeWithSignature("TooShort()"));
        veTFI.previewPoints(100e18, 1 hours - 1);

        console.log("Revert if duration is too long");
        vm.expectRevert(abi.encodeWithSignature("TooLong()"));
        veTFI.previewPoints(100e18, 365 days * 3 + 1);

        console.log("Use epoch if block.timestamp is lower than epoch");
        (, uint256 ends) = veTFI.previewPoints(100e18, 10 days);
        assertEq(ends, epoch + 10 days, "Invalid ends");

        console.log("Use block.timestamp if block.timestamp is greater than epoch");
        vm.warp(block.timestamp + 5 days);
        (, ends) = veTFI.previewPoints(100e18, 10 days);
        assertEq(ends, block.timestamp + 10 days, "Invalid ends");

        console.log("Return valid points and ends");
        uint256 duration = 60 days;
        uint256 amount = 100e18;
        (uint256 points, uint256 _ends) = veTFI.previewPoints(amount, duration);
        assertEq(_ends, block.timestamp + duration, "Invalid ends");
        uint256 multiplier = PRBMathUD60x18.pow(YEAR_BASE, ((_ends - epoch) * 1e18) / 365 days);
        assertEq(points, (amount * multiplier) / 1e18, "Invalid points");
    }

    function _stake(uint256 amount, uint256 duration, address from, address to) internal {
        vm.startPrank(from);

        veTFI.stake(amount, duration, to);

        vm.stopPrank();
    }

    function _stakeVesting(uint256 amount, uint256 duration, address to) internal {
        vm.startPrank(vesting);

        veTFI.stakeVesting(amount, duration, to);

        vm.stopPrank();
    }

    function _validateLockup(address user, uint256 idx, uint256 amount, uint256 ends, uint256 points, bool isVesting)
        internal
    {
        (uint128 _amount, uint128 _ends, uint256 _points, bool _isVesting) = veTFI.lockups(user, idx);

        assertEq(amount, uint256(_amount), "Amount is invalid");
        assertEq(ends, uint256(_ends), "End timestamp is invalid");
        assertEq(points, _points, "Points is invalid");
        assertEq(isVesting, _isVesting, "isVesting is invalid");
    }
}
