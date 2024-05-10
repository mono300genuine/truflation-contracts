// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../../src/token/TruflationToken.sol";
import "../../src/token/TrufVesting.sol";
import "../../src/token/VotingEscrowTruf.sol";
import "../../src/staking/VirtualStakingRewards.sol";

contract VotingEscrowTrufTest is Test {
    event Stake(
        address indexed user, bool indexed isVesting, uint256 lockupId, uint256 amount, uint256 end, uint256 points
    );
    event Unstake(
        address indexed user, bool indexed isVesting, uint256 lockupId, uint256 amount, uint256 end, uint256 points
    );
    event Migrated(address indexed oldUser, address indexed newUser, uint256 oldLockupId, uint256 newLockupId);
    event Cancelled(address indexed user, uint256 lockupId, uint256 amount, uint256 points);

    TruflationToken public trufToken;
    VotingEscrowTruf public veTRUF;
    VirtualStakingRewards public trufStakingRewards;

    // Config
    string public name = "Voting Escrowed TRUF";
    string public symbol = "veTRUF";

    uint256 public constant MIN_STAKE_DURATION = 1 hours;
    uint256 public MAX_STAKE_DURATION = 365 days * 3; // 3 years
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

        vm.startPrank(owner);
        trufToken = new TruflationToken();
        trufToken.transfer(alice, trufToken.totalSupply() / 3);
        trufToken.transfer(vesting, trufToken.totalSupply() / 3);
        trufStakingRewards = new VirtualStakingRewards(owner, address(trufToken));
        veTRUF =
            new VotingEscrowTruf(address(trufToken), address(vesting), MIN_STAKE_DURATION, address(trufStakingRewards));
        trufStakingRewards.setOperator(address(veTRUF));
        trufToken.transfer(address(trufStakingRewards), 200e18);
        trufStakingRewards.notifyRewardAmount(200e18);

        vm.stopPrank();

        vm.startPrank(alice);
        trufToken.approve(address(veTRUF), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(vesting);
        trufToken.approve(address(veTRUF), type(uint256).max);
        vm.stopPrank();
    }

    function testConstructorSuccess() external {
        console.log("Check initial variables");
        assertEq(address(veTRUF.trufToken()), address(trufToken), "TRUF Token is invalid");
        assertEq(veTRUF.trufVesting(), vesting, "Vesting is invalid");
        assertEq(veTRUF.minStakeDuration(), MIN_STAKE_DURATION, "MIN_STAKE_DURATION is invalid");
        assertEq(veTRUF.MAX_DURATION(), MAX_STAKE_DURATION, "MAX_STAKE_DURATION is invalid");
        assertEq(address(veTRUF.stakingRewards()), address(trufStakingRewards), "StakingRewards is invalid");
        assertEq(veTRUF.name(), name, "Name is invalid");
        assertEq(veTRUF.symbol(), symbol, "Symbol is invalid");
        assertEq(veTRUF.decimals(), 18, "Decimal is invalid");
    }

    function testTransfer_RevertAlways() external {
        console.log("Always revert when transferring token");

        _stake(100e18, 30 days, alice, alice);

        assertNotEq(veTRUF.balanceOf(alice), 0, "Alice does not have veTRUF");

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("TransferDisabled()"));
        veTRUF.transfer(bob, 1);

        vm.stopPrank();
    }

    function testStake_FirstTime() external {
        console.log("StakeTo first time");

        uint256 amount = 100e18;
        uint256 duration = 30 days;

        uint256 points = veTRUF.previewPoints(amount, duration);
        uint256 ends = block.timestamp + duration;
        assertNotEq(points, 0, "Points should be non-zero");

        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true, address(veTRUF));
        emit Stake(alice, false, 0, amount, ends, points);

        veTRUF.stake(amount, duration);

        vm.stopPrank();

        assertEq(veTRUF.balanceOf(alice), points, "Alice should have balance");
        assertEq(veTRUF.balanceOf(bob), 0, "Bob should not have balance");
        assertEq(trufStakingRewards.balanceOf(alice), points, "Alice should have staking balance");
        assertEq(trufToken.balanceOf(address(veTRUF)), amount, "TRUF token should be transferred");
        assertEq(veTRUF.delegates(alice), alice, "Delegate is invalid");

        _validateLockup(alice, 0, amount, duration, ends, points, false);
    }

    function testStakeTo_FirstTime() external {
        console.log("StakeTo first time");

        uint256 amount = 100e18;
        uint256 duration = 30 days;

        uint256 points = veTRUF.previewPoints(amount, duration);
        uint256 ends = block.timestamp + duration;
        assertNotEq(points, 0, "Points should be non-zero");

        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true, address(veTRUF));
        emit Stake(bob, false, 0, amount, ends, points);

        veTRUF.stake(amount, duration, bob);

        vm.stopPrank();

        assertEq(veTRUF.balanceOf(alice), 0, "Alice should not have balance");
        assertEq(veTRUF.balanceOf(bob), points, "Bob should have balance");
        assertEq(trufStakingRewards.balanceOf(bob), points, "Bob should have staking balance");
        assertEq(trufToken.balanceOf(address(veTRUF)), amount, "TRUF token should be transferred");
        assertEq(veTRUF.delegates(bob), bob, "Delegate is invalid");

        _validateLockup(bob, 0, amount, duration, ends, points, false);
    }

    function testStake_SecondTime() external {
        console.log("Stake second time");

        _stake(100e18, 30 days, alice, alice);

        uint256 amount = 1000e18;
        uint256 duration = 60 days;

        uint256 prevBalance = veTRUF.balanceOf(alice);

        uint256 points = veTRUF.previewPoints(amount, duration);
        uint256 ends = block.timestamp + duration;
        assertNotEq(points, 0, "Points should be non-zero");

        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true, address(veTRUF));
        emit Stake(alice, false, 1, amount, ends, points);

        veTRUF.stake(amount, duration);

        vm.stopPrank();

        assertEq(veTRUF.balanceOf(alice), prevBalance + points, "Alice should have balance");
        assertEq(trufStakingRewards.balanceOf(alice), prevBalance + points, "Alice should have staking balance");
        assertEq(trufToken.balanceOf(address(veTRUF)), amount + 100e18, "TRUF token should be transferred");
        assertEq(veTRUF.delegates(alice), alice, "Delegate is invalid");

        _validateLockup(alice, 1, amount, duration, ends, points, false);
    }

    function testStakeTo_SecondTime() external {
        console.log("StakeTo second time");

        _stake(100e18, 30 days, alice, bob);

        uint256 amount = 1000e18;
        uint256 duration = 60 days;

        uint256 prevBalance = veTRUF.balanceOf(bob);

        uint256 points = veTRUF.previewPoints(amount, duration);
        uint256 ends = block.timestamp + duration;
        assertNotEq(points, 0, "Points should be non-zero");

        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true, address(veTRUF));
        emit Stake(bob, false, 1, amount, ends, points);

        veTRUF.stake(amount, duration, bob);

        vm.stopPrank();

        assertEq(veTRUF.balanceOf(bob), prevBalance + points, "Bob should have balance");
        assertEq(trufStakingRewards.balanceOf(bob), prevBalance + points, "Bob should have staking balance");
        assertEq(trufToken.balanceOf(address(veTRUF)), amount + 100e18, "TRUF token should be transferred");
        assertEq(veTRUF.delegates(bob), bob, "Delegate is invalid");

        _validateLockup(bob, 1, amount, duration, ends, points, false);
    }

    function testStake_DoNotChangeDelegateeIfAlreadySet() external {
        console.log("Do not change delegatee if already set");

        vm.startPrank(alice);

        veTRUF.delegate(bob);

        vm.stopPrank();

        _stake(100e18, 30 days, alice, alice);

        assertEq(veTRUF.delegates(alice), bob, "Delegate is invalid");
    }

    function testStakeFailure() external {
        vm.startPrank(alice);

        console.log("Revert if amount is 0");
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        veTRUF.stake(0, 30 days, bob);

        console.log("Revert if points is 0");
        vm.expectRevert(abi.encodeWithSignature("ZeroPoints()"));
        veTRUF.stake(1, MIN_STAKE_DURATION, bob);

        console.log("Revert if to is address(0)");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        veTRUF.stake(100e18, 30 days, address(0));

        console.log("Revert if amount is greater than available balance");
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        veTRUF.stake(uint256(type(uint128).max) + 1, 30 days, bob);

        vm.stopPrank();
    }

    function testStakeVesting() external {
        console.log("Stake vesting");

        uint256 amount = 100e18;
        uint256 duration = 30 days;

        uint256 points = veTRUF.previewPoints(amount, duration);
        uint256 ends = block.timestamp + duration;
        assertNotEq(points, 0, "Points should be non-zero");

        vm.startPrank(vesting);

        vm.expectEmit(true, true, true, true, address(veTRUF));
        emit Stake(bob, true, 0, amount, ends, points);

        assertEq(veTRUF.stakeVesting(amount, duration, bob), 0, "Lockup id is invalid");

        vm.stopPrank();

        assertEq(veTRUF.balanceOf(alice), 0, "Alice should not have balance");
        assertEq(veTRUF.balanceOf(bob), points, "Bob should have balance");
        assertEq(trufStakingRewards.balanceOf(bob), points, "Bob should have staking balance");
        assertEq(trufToken.balanceOf(address(veTRUF)), amount, "TRUF token should be transferred");
        assertEq(veTRUF.delegates(bob), bob, "Delegate is invalid");

        _validateLockup(bob, 0, amount, duration, ends, points, true);
    }

    function testStakeVestingFailure() external {
        vm.startPrank(alice);

        console.log("Revert if msg.sender is not vesting");
        vm.expectRevert(abi.encodeWithSignature("Forbidden(address)", alice));
        veTRUF.stakeVesting(100e18, 30 days, vesting);

        vm.stopPrank();

        vm.startPrank(vesting);

        console.log("Revert if to is vesting");
        vm.expectRevert(abi.encodeWithSignature("InvalidAccount()"));
        veTRUF.stakeVesting(100e18, 30 days, vesting);

        vm.stopPrank();
    }

    function testUnstake() external {
        console.log("Unstake lockup");

        uint256 amount = 100e18;
        uint256 duration = 30 days;

        _stake(amount, duration, alice, bob);

        uint256 points = veTRUF.previewPoints(amount, duration);
        uint256 ends = block.timestamp + duration;
        assertNotEq(points, 0, "Points should be non-zero");

        vm.warp(ends);

        vm.startPrank(bob);

        vm.expectEmit(true, true, true, true, address(veTRUF));
        emit Unstake(bob, false, 0, amount, ends, points);

        veTRUF.unstake(0);

        vm.stopPrank();

        assertEq(veTRUF.balanceOf(bob), 0, "Bob should have no balance");
        assertEq(trufStakingRewards.balanceOf(bob), 0, "Bob should have no staking balance");
        assertEq(trufToken.balanceOf(address(veTRUF)), 0, "TRUF token should be transferred from veTRUF");
        assertEq(trufToken.balanceOf(bob), amount, "TRUF token should be transferred to bob");

        _validateLockup(bob, 0, 0, 0, 0, 0, false);
    }

    function testUnstakeFailures() external {
        uint256 amount = 100e18;
        uint256 duration = 30 days;

        _stake(amount, duration, alice, bob);

        uint256 points = veTRUF.previewPoints(amount, duration);
        uint256 ends = block.timestamp + duration;
        assertNotEq(points, 0, "Points should be non-zero");

        console.log("Revert to unstake if trying to unstake as vesting");

        vm.startPrank(vesting);

        vm.expectRevert(abi.encodeWithSignature("NoAccess()"));
        veTRUF.unstakeVesting(bob, 0, false);

        vm.stopPrank();

        vm.startPrank(bob);

        console.log("Revert to unstake if lockup period not ended");

        vm.warp(block.timestamp + 10 days);
        vm.expectRevert(abi.encodeWithSignature("LockupNotEnded()"));
        veTRUF.unstake(0);

        console.log("Revert to unstake if already unstaked");

        vm.warp(ends);
        veTRUF.unstake(0);

        vm.expectRevert(abi.encodeWithSignature("LockupAlreadyUnstaked()"));
        veTRUF.unstake(0);

        vm.stopPrank();
    }

    function testUnstakeVesting_NotForce() external {
        console.log("Unstake vesting lockup");

        uint256 amount = 100e18;
        uint256 duration = 30 days;

        _stakeVesting(amount, duration, bob);

        uint256 prevVestingBal = trufToken.balanceOf(vesting);

        uint256 points = veTRUF.previewPoints(amount, duration);
        uint256 ends = block.timestamp + duration;
        assertNotEq(points, 0, "Points should be non-zero");

        vm.warp(ends);

        vm.startPrank(vesting);

        vm.expectEmit(true, true, true, true, address(veTRUF));
        emit Unstake(bob, true, 0, amount, ends, points);

        veTRUF.unstakeVesting(bob, 0, false);

        vm.stopPrank();

        assertEq(veTRUF.balanceOf(bob), 0, "Bob should have no balance");
        assertEq(trufStakingRewards.balanceOf(bob), 0, "Bob should have no staking balance");
        assertEq(trufToken.balanceOf(address(veTRUF)), 0, "TRUF token should be transferred from veTRUF");
        assertEq(trufToken.balanceOf(vesting), prevVestingBal + amount, "TRUF token should be transferred to vesting");

        _validateLockup(bob, 0, 0, 0, 0, 0, false);
    }

    function testUnstakeVesting_Force() external {
        console.log("Unstake vesting lockup forcefully before ends");

        uint256 amount = 100e18;
        uint256 duration = 30 days;

        _stakeVesting(amount, duration, bob);

        uint256 prevVestingBal = trufToken.balanceOf(vesting);

        uint256 points = veTRUF.previewPoints(amount, duration);
        assertNotEq(points, 0, "Points should be non-zero");

        vm.warp(block.timestamp + 10 days);

        vm.startPrank(vesting);

        vm.expectEmit(true, true, true, true, address(veTRUF));
        emit Cancelled(bob, 0, amount, points);

        veTRUF.unstakeVesting(bob, 0, true);

        vm.stopPrank();

        assertEq(veTRUF.balanceOf(bob), 0, "Bob should have no balance");
        assertEq(trufStakingRewards.balanceOf(bob), 0, "Bob should have no staking balance");
        assertEq(trufToken.balanceOf(address(veTRUF)), 0, "TRUF token should be transferred from veTRUF");
        assertEq(trufToken.balanceOf(vesting), prevVestingBal + amount, "TRUF token should be transferred to vesting");

        _validateLockup(bob, 0, 0, 0, 0, 0, false);
    }

    function testUnstakeVestingFailures() external {
        uint256 amount = 100e18;
        uint256 duration = 30 days;

        _stakeVesting(amount, duration, bob);

        console.log("Revert to unstake if trying to unstake as normal");

        vm.startPrank(bob);

        vm.expectRevert(abi.encodeWithSignature("NoAccess()"));
        veTRUF.unstake(0);

        console.log("Revert if msg.sender is not vesting");
        vm.expectRevert(abi.encodeWithSignature("Forbidden(address)", bob));
        veTRUF.unstakeVesting(bob, 0, false);

        vm.stopPrank();
    }

    function testExtendLock() external {
        console.log("Extend duration and increase amount of lockup");

        uint256 amount = 100e18;
        uint256 duration = 30 days;

        _stake(amount, duration, alice, alice);

        vm.warp(block.timestamp + 10 days);

        uint256 extendDuration = 60 days;
        uint256 increaseAmount = 50e18;

        (,, uint128 _ends, uint256 _points,) = veTRUF.lockups(alice, 0);

        uint256 newEnds = _ends + extendDuration;

        uint256 mintAmount =
            ((amount * extendDuration) + (increaseAmount * (newEnds - block.timestamp))) / veTRUF.MAX_DURATION();

        assertNotEq(mintAmount, 0, "Points should be non-zero");

        uint256 newPoints = _points + mintAmount;

        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true, address(veTRUF));
        emit Stake(alice, false, 0, amount + increaseAmount, newEnds, newPoints);

        veTRUF.extendLock(0, increaseAmount, extendDuration);

        vm.stopPrank();

        assertEq(veTRUF.balanceOf(alice), newPoints, "Mint increased points to alice");
        assertEq(trufStakingRewards.balanceOf(alice), newPoints, "Stake increased points to staking rewards");

        _validateLockup(alice, 0, amount + increaseAmount, duration + extendDuration, newEnds, newPoints, false);
    }

    function testExtendLockFailures() external {
        uint256 amount = 100e18;
        uint256 duration = 30 days;

        _stake(amount, duration, alice, alice);

        uint256 points = veTRUF.previewPoints(amount, duration);
        assertNotEq(points, 0, "Points should be non-zero");

        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSignature("NotIncrease()"));
        veTRUF.extendLock(0, 0, 0);

        vm.stopPrank();

        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSignature("TooLong()"));
        veTRUF.extendLock(0, 100e18, 365 days * 3 - 20 days);

        vm.stopPrank();

        uint256 extendDuration = 60 days;

        console.log("Revert to extend if trying to extend as vesting");

        vm.warp(block.timestamp + 10 days);

        vm.startPrank(vesting);

        vm.expectRevert(abi.encodeWithSignature("NoAccess()"));
        veTRUF.extendVestingLock(alice, 0, 100e18, extendDuration);

        vm.stopPrank();

        console.log("Revert to extend if already ended");
        vm.warp(block.timestamp + 30 days);
        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSignature("AlreadyEnded()"));
        veTRUF.extendLock(0, 0, extendDuration);

        vm.stopPrank();
    }

    function testExtendVestingLock() external {
        console.log("Extend duration of vesting lockup");

        uint256 amount = 100e18;
        uint256 duration = 30 days;

        _stakeVesting(amount, duration, alice);

        (,, uint128 _ends, uint256 _points,) = veTRUF.lockups(alice, 0);

        vm.warp(block.timestamp + 10 days);

        uint256 extendDuration = 60 days;
        uint256 increaseAmount = 50e18;

        uint256 newEnds = _ends + extendDuration;

        uint256 mintAmount = ((amount * extendDuration) + (increaseAmount * 80 days)) / veTRUF.MAX_DURATION();

        assertNotEq(mintAmount, 0, "Points should be non-zero");

        uint256 newPoints = _points + mintAmount;

        vm.startPrank(vesting);

        vm.expectEmit(true, true, true, true, address(veTRUF));
        emit Stake(alice, true, 0, amount + increaseAmount, newEnds, newPoints);

        veTRUF.extendVestingLock(alice, 0, increaseAmount, extendDuration);

        vm.stopPrank();

        assertEq(veTRUF.balanceOf(alice), newPoints, "Mint increased points to alice");
        assertEq(trufStakingRewards.balanceOf(alice), newPoints, "Stake increased points to staking rewards");

        _validateLockup(alice, 0, amount + increaseAmount, duration + extendDuration, newEnds, newPoints, true);
    }

    function testExtendVestingLockFailures() external {
        uint256 amount = 100e18;
        uint256 duration = 30 days;

        _stakeVesting(amount, duration, alice);

        console.log("Revert to extend if trying to extend as normal");

        vm.warp(block.timestamp + 10 days);

        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSignature("NoAccess()"));
        veTRUF.extendLock(0, 50e18, duration);

        console.log("Revert if msg.sender is not vesting");
        vm.expectRevert(abi.encodeWithSignature("Forbidden(address)", alice));
        veTRUF.extendVestingLock(alice, 0, 50e18, duration);

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

        uint256 alicePoints = veTRUF.previewPoints(aliceAmount, aliceDuration);

        uint256 points = veTRUF.previewPoints(amount, duration);
        uint256 ends = block.timestamp + duration;
        assertNotEq(points, 0, "Points should be non-zero");

        assertEq(veTRUF.getVotes(alice), alicePoints + points, "Voting power should be updated");
        vm.warp(block.timestamp + 10 days);

        uint256 reward = trufStakingRewards.earned(alice);
        assertNotEq(reward, 0, "Rewards should be non-zero");

        vm.startPrank(vesting);

        vm.expectEmit(true, true, true, true, address(veTRUF));
        emit Migrated(alice, bob, 1, 0);

        veTRUF.migrateVestingLock(alice, bob, 1);

        vm.stopPrank();

        assertEq(veTRUF.balanceOf(alice), alicePoints, "Points should be burned");
        assertEq(trufStakingRewards.balanceOf(alice), alicePoints, "Stake amount should be reduced");
        assertEq(veTRUF.balanceOf(bob), points, "Points should be minted to new user");
        assertEq(trufStakingRewards.balanceOf(bob), points, "Stake amount should be moved to new user");
        assertEq(veTRUF.getVotes(alice), alicePoints, "Voting power of old user should be removed");
        assertEq(veTRUF.getVotes(bob), points, "Voting power should be moved to new user");
        assertEq(trufStakingRewards.earned(alice), 0, "Reset old users reward");
        assertEq(trufToken.balanceOf(bob), reward, "Reward should be paid to new user");

        _validateLockup(alice, 1, 0, 0, 0, 0, false);
        _validateLockup(bob, 0, amount, duration, ends, points, true);
    }

    function testMigrateVestingLockFailures() external {
        _stakeVesting(100e18, 30 days, alice);
        _stake(100e18, 30 days, alice, alice);

        console.log("Revert if msg.sender is not vesting");
        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSignature("Forbidden(address)", alice));
        veTRUF.migrateVestingLock(alice, bob, 0);

        vm.stopPrank();

        vm.startPrank(vesting);

        console.log("Revert if old user and new user is same");
        vm.expectRevert(abi.encodeWithSignature("NotMigrate()"));
        veTRUF.migrateVestingLock(alice, alice, 0);

        console.log("Revert if new user is address(0)");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        veTRUF.migrateVestingLock(alice, address(0), 0);

        console.log("Revert to migrate non-vesting lockup");
        vm.expectRevert(abi.encodeWithSignature("NoAccess()"));
        veTRUF.migrateVestingLock(alice, bob, 1);

        vm.stopPrank();
    }

    function testClaimReward() external {
        console.log("Claim reward");

        uint256 amount = 100e18;
        uint256 duration = 30 days;

        _stake(amount, duration, alice, bob);

        vm.warp(block.timestamp + 10 days);

        uint256 earned = trufStakingRewards.earned(bob);
        assertNotEq(earned, 0, "Earned reward should be non-zero");

        vm.startPrank(bob);

        veTRUF.claimReward();

        vm.stopPrank();

        assertEq(trufStakingRewards.earned(bob), 0, "Earned reward should be zero");
        assertEq(trufToken.balanceOf(bob), earned, "Bob should receive reward");
    }

    function testPreviewPoints() external {
        console.log("Revert if duration is too short");
        vm.expectRevert(abi.encodeWithSignature("TooShort()"));
        veTRUF.previewPoints(100e18, 1 hours - 1);

        console.log("Revert if duration is too long");
        vm.expectRevert(abi.encodeWithSignature("TooLong()"));
        veTRUF.previewPoints(100e18, 365 days * 3 + 1);

        console.log("Return valid points and ends");
        uint256 duration = 60 days;
        uint256 amount = 100e18;
        uint256 points = veTRUF.previewPoints(amount, duration);
        assertEq(points, (amount * duration) / (365 days * 3), "Invalid points");
    }

    function _stake(uint256 amount, uint256 duration, address from, address to) internal {
        vm.startPrank(from);

        veTRUF.stake(amount, duration, to);

        vm.stopPrank();
    }

    function _stakeVesting(uint256 amount, uint256 duration, address to) internal {
        vm.startPrank(vesting);

        veTRUF.stakeVesting(amount, duration, to);

        vm.stopPrank();
    }

    function _validateLockup(
        address user,
        uint256 idx,
        uint256 amount,
        uint256 duration,
        uint256 ends,
        uint256 points,
        bool isVesting
    ) internal {
        (uint128 _amount, uint128 _duration, uint128 _ends, uint256 _points, bool _isVesting) =
            veTRUF.lockups(user, idx);

        assertEq(amount, uint256(_amount), "Amount is invalid");
        assertEq(duration, uint256(_duration), "Duration is invalid");
        assertEq(ends, uint256(_ends), "End timestamp is invalid");
        assertEq(points, _points, "Points is invalid");
        assertEq(isVesting, _isVesting, "isVesting is invalid");
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return b > a ? a : b;
    }
}
