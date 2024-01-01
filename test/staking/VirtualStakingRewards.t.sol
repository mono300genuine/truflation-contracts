// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../../src/token/TruflationToken.sol";
import "../../src/token/VotingEscrowTruf.sol";
import "../../src/staking/VirtualStakingRewards.sol";

contract VirtualStakingRewardsTest is Test {
    TruflationToken public trufToken;
    VirtualStakingRewards public trufStakingRewards;

    // Users
    address public alice;
    address public bob;
    address public owner;
    address public operator;
    address public rewardsDistribuion;

    function setUp() public {
        alice = address(uint160(uint256(keccak256(abi.encodePacked("Alice")))));
        bob = address(uint160(uint256(keccak256(abi.encodePacked("Bob")))));
        owner = address(uint160(uint256(keccak256(abi.encodePacked("Owner")))));
        operator = address(uint160(uint256(keccak256(abi.encodePacked("Operator")))));
        rewardsDistribuion = address(uint160(uint256(keccak256(abi.encodePacked("RewardsDistribuion")))));

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(owner, "Owner");
        vm.label(operator, "Operator");
        vm.label(rewardsDistribuion, "RewardsDistribuion");

        vm.warp(1696816730);

        vm.startPrank(owner);
        trufToken = new TruflationToken();
        trufStakingRewards = new VirtualStakingRewards(rewardsDistribuion, address(trufToken));
        trufStakingRewards.setOperator(operator);
        trufToken.transfer(rewardsDistribuion, trufToken.totalSupply());

        vm.stopPrank();
    }

    function testConstructorSuccess() external {
        console.log("Check initial variables");
        assertEq(address(trufStakingRewards.rewardsToken()), address(trufToken), "Reward Token is invalid");
        assertEq(trufStakingRewards.owner(), owner, "Owner is invalid");
        assertEq(trufStakingRewards.rewardsDistribution(), rewardsDistribuion, "rewardsDistribuion is invalid");
        assertEq(trufStakingRewards.totalSupply(), 0, "Initial supply is invalid");
    }

    function testConstructorFailure() external {
        console.log("Should revert if rewards token is address(0)");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new VirtualStakingRewards(rewardsDistribuion, address(0));

        console.log("Should revert if rewardsDistribution is address(0)");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new VirtualStakingRewards(address(0), address(trufToken));
    }

    function testSetRewardsDuration() external {
        console.log("Set rewards duration");

        vm.startPrank(owner);

        uint256 newDuration = 14 days;

        vm.expectEmit(true, true, true, true, address(trufStakingRewards));
        emit RewardsDurationUpdated(newDuration);

        trufStakingRewards.setRewardsDuration(newDuration);

        assertEq(trufStakingRewards.rewardsDuration(), newDuration, "RewardsDuration is invalid");

        vm.stopPrank();
    }

    function testSetRewardsDurationFailure() external {
        console.log("Should revert to set 0 as rewardsDuration");

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        trufStakingRewards.setRewardsDuration(0);

        vm.stopPrank();

        console.log("Should revert when sender is not owner");
        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        trufStakingRewards.setRewardsDuration(14 days);

        vm.stopPrank();

        _notifyReward(100e18);
        vm.warp(block.timestamp + 3 days);

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("RewardPeriodNotFinished()"));
        trufStakingRewards.setRewardsDuration(14 days);
    }

    function testLastTimeRewardApplicable() external {
        console.log("Return block timestamp if reward period is not finished");

        uint256 rewardAmount = 100e18;
        _notifyReward(rewardAmount);

        vm.warp(block.timestamp + 3 days);

        assertEq(
            trufStakingRewards.lastTimeRewardApplicable(),
            block.timestamp,
            "Return block timestamp if reward period is not finished"
        );

        vm.warp(block.timestamp + 5 days);

        assertEq(
            trufStakingRewards.lastTimeRewardApplicable(),
            trufStakingRewards.periodFinish(),
            "Return periodFinish if reward period is finished"
        );
    }

    function testRewardPerToken() external {
        console.log("Return block timestamp if reward period is not finished");

        uint256 rewardAmount = 100e18;
        _notifyReward(rewardAmount);

        uint256 aliceAmount = 5e18;
        uint256 bobAmount = 15e18;
        uint256 totalSupply = aliceAmount + bobAmount;

        _stake(alice, aliceAmount);
        vm.warp(block.timestamp + 3 days);
        _stake(bob, bobAmount);
        vm.warp(block.timestamp + 1 days);

        uint256 rewardRate = rewardAmount / 7 days;
        assertEq(
            trufStakingRewards.rewardPerToken(),
            trufStakingRewards.rewardPerTokenStored() + (1 days * rewardRate * 1e18 / totalSupply),
            "RewardPerToken is invalid"
        );

        console.log("Return rewardPerTokenStored if totalSupply is zero");
        _withdraw(alice, aliceAmount);
        _withdraw(bob, bobAmount);

        vm.warp(block.timestamp + 1 days);
        assertEq(
            trufStakingRewards.rewardPerToken(), trufStakingRewards.rewardPerTokenStored(), "RewardPerToken is invalid"
        );
    }

    function testEarned() external {
        console.log("Test earned amount");

        uint256 rewardAmount = 100e18;
        _notifyReward(rewardAmount);

        uint256 aliceAmount = 5e18;
        uint256 aliceAmount2 = 10e18;
        uint256 bobAmount = 15e18;

        _stake(alice, aliceAmount);
        vm.warp(block.timestamp + 3 days);
        _stake(bob, bobAmount);
        vm.warp(block.timestamp + 1 days);
        _stake(alice, aliceAmount2);
        vm.warp(block.timestamp + 1 days);

        assertEq(
            trufStakingRewards.earned(alice),
            (aliceAmount + aliceAmount2)
                * (trufStakingRewards.rewardPerToken() - trufStakingRewards.userRewardPerTokenPaid(alice)) / 1e18
                + trufStakingRewards.rewards(alice),
            "Earned amount is invalid"
        );
    }

    function testGetRewardForDuration() external {
        console.log("Get reward for duration");

        uint256 rewardAmount = 100e18;
        _notifyReward(rewardAmount);

        uint256 rewardRate = rewardAmount / 7 days;
        assertEq(trufStakingRewards.getRewardForDuration(), rewardRate * 7 days, "Reward for duration is invalid");
    }

    function testStake_FirstTime() external {
        console.log("Stake first time");

        uint256 amount = 10e18;

        vm.startPrank(operator);

        vm.expectEmit(true, true, true, true, address(trufStakingRewards));
        emit Staked(alice, amount);

        trufStakingRewards.stake(alice, amount);

        assertEq(trufStakingRewards.totalSupply(), amount, "Total supply is invalid");
        assertEq(trufStakingRewards.balanceOf(alice), amount, "Balance is invalid");

        vm.stopPrank();
    }

    function testStake_SecondTime() external {
        console.log("Stake second time");

        uint256 rewardAmount = 100e18;
        _notifyReward(rewardAmount);

        uint256 firstAmount = 10e18;
        uint256 secondAmount = 20e18;

        vm.startPrank(operator);

        trufStakingRewards.stake(alice, firstAmount);

        vm.warp(block.timestamp + 3 days);

        vm.expectEmit(true, true, true, true, address(trufStakingRewards));
        emit Staked(alice, secondAmount);

        trufStakingRewards.stake(alice, secondAmount);

        // Validate supply and balance
        assertEq(trufStakingRewards.totalSupply(), firstAmount + secondAmount, "Total supply is invalid");
        assertEq(trufStakingRewards.balanceOf(alice), firstAmount + secondAmount, "Balance is invalid");

        // Validate rewards updates
        assertEq(trufStakingRewards.lastUpdateTime(), block.timestamp, "Last updated time is invalid");
        assertEq(trufStakingRewards.rewards(alice), trufStakingRewards.earned(alice), "Reward was not updated");
        assertEq(
            trufStakingRewards.userRewardPerTokenPaid(alice),
            trufStakingRewards.rewardPerTokenStored(),
            "UserRewardPerTokenPaid was not updated"
        );

        vm.stopPrank();
    }

    function testStakeFailure() external {
        console.log("Should revert to stake for address(0)");

        vm.startPrank(operator);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        trufStakingRewards.stake(address(0), 1e18);

        console.log("Should revert to stake for zero amount");
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        trufStakingRewards.stake(alice, 0);

        vm.stopPrank();

        console.log("Should revert when sender is not operator");
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("Forbidden(address)", owner));
        trufStakingRewards.stake(alice, 1e18);

        vm.stopPrank();
    }

    function testWithdraw() external {
        console.log("Withdraw");

        uint256 rewardAmount = 100e18;
        _notifyReward(rewardAmount);

        uint256 stakeAmount = 10e18;
        uint256 amount = 5e18;

        vm.startPrank(operator);

        trufStakingRewards.stake(alice, stakeAmount);

        vm.warp(block.timestamp + 3 days);

        vm.expectEmit(true, true, true, true, address(trufStakingRewards));
        emit Withdrawn(alice, amount);

        trufStakingRewards.withdraw(alice, amount);

        // Validate supply and balance
        assertEq(trufStakingRewards.totalSupply(), stakeAmount - amount, "Total supply is invalid");
        assertEq(trufStakingRewards.balanceOf(alice), stakeAmount - amount, "Balance is invalid");

        // Validate rewards updates
        assertEq(trufStakingRewards.lastUpdateTime(), block.timestamp, "Last updated time is invalid");
        assertEq(trufStakingRewards.rewards(alice), trufStakingRewards.earned(alice), "Reward was not updated");
        assertEq(
            trufStakingRewards.userRewardPerTokenPaid(alice),
            trufStakingRewards.rewardPerTokenStored(),
            "UserRewardPerTokenPaid was not updated"
        );

        vm.stopPrank();
    }

    function testWithdrawFailure() external {
        vm.startPrank(operator);
        console.log("Should revert to withdraw zero amount");
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        trufStakingRewards.withdraw(alice, 0);

        vm.stopPrank();

        console.log("Should revert when sender is not operator");
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("Forbidden(address)", owner));
        trufStakingRewards.withdraw(alice, 1e18);

        vm.stopPrank();
    }

    function testGetReward() external {
        console.log("Get reward");

        uint256 rewardAmount = 100e18;
        _notifyReward(rewardAmount);

        uint256 stakeAmount = 10e18;

        vm.startPrank(operator);

        trufStakingRewards.stake(alice, stakeAmount);

        vm.warp(block.timestamp + 3 days);

        uint256 reward = trufStakingRewards.earned(alice);
        vm.expectEmit(true, true, true, true, address(trufStakingRewards));
        emit RewardPaid(alice, reward);

        trufStakingRewards.getReward(alice);

        // Validate supply and balance
        assertEq(trufStakingRewards.totalSupply(), stakeAmount, "Total supply is invalid");
        assertEq(trufStakingRewards.balanceOf(alice), stakeAmount, "Balance is invalid");

        // Validate rewards updates
        assertEq(trufStakingRewards.lastUpdateTime(), block.timestamp, "Last updated time is invalid");
        assertEq(trufStakingRewards.rewards(alice), 0, "Reward was not updated");
        assertEq(
            trufStakingRewards.userRewardPerTokenPaid(alice),
            trufStakingRewards.rewardPerTokenStored(),
            "UserRewardPerTokenPaid was not updated"
        );

        assertEq(trufToken.balanceOf(alice), reward, "Received reward is invalid");

        vm.stopPrank();
    }

    function testGetReward_DoNotRevert_WhenRewardIsZero() external {
        console.log("Do not revert when reward amount is zero");

        vm.startPrank(operator);

        trufStakingRewards.getReward(alice);

        assertEq(trufToken.balanceOf(alice), 0, "Reward should be zero");

        vm.stopPrank();
    }

    function testExit() external {
        console.log("Exit from staking(withdraw all balance, and claim reward)");

        uint256 rewardAmount = 100e18;
        _notifyReward(rewardAmount);

        uint256 stakeAmount = 10e18;

        _stake(alice, stakeAmount);
        vm.startPrank(operator);

        vm.warp(block.timestamp + 3 days);

        uint256 reward = trufStakingRewards.earned(alice);

        trufStakingRewards.exit(alice);

        // Validate supply and balance
        assertEq(trufStakingRewards.totalSupply(), 0, "Total supply is invalid");
        assertEq(trufStakingRewards.balanceOf(alice), 0, "Balance is invalid");

        // Validate rewards updates
        assertEq(trufStakingRewards.lastUpdateTime(), block.timestamp, "Last updated time is invalid");
        assertEq(trufStakingRewards.rewards(alice), 0, "Reward was not updated");
        assertEq(
            trufStakingRewards.userRewardPerTokenPaid(alice),
            trufStakingRewards.rewardPerTokenStored(),
            "UserRewardPerTokenPaid was not updated"
        );

        assertEq(trufToken.balanceOf(alice), reward, "Received reward is invalid");

        vm.stopPrank();
    }

    function testExit_WhenEmptyBalance() external {
        console.log("Exit when balance is empty");

        uint256 rewardAmount = 100e18;
        _notifyReward(rewardAmount);

        uint256 stakeAmount = 10e18;

        _stake(alice, stakeAmount);

        vm.warp(block.timestamp + 3 days);

        _withdraw(alice, stakeAmount);

        uint256 reward = trufStakingRewards.earned(alice);

        assertEq(trufStakingRewards.rewards(alice), reward, "Reward was not updated");

        trufStakingRewards.exit(alice);
        assertEq(trufStakingRewards.rewards(alice), 0, "Reward was not updated");

        assertEq(trufToken.balanceOf(alice), reward, "Received reward is invalid");
    }

    function testNotifyRewardAmount() external {
        console.log("Notify rewards");

        uint256 rewards = 100e18;
        vm.startPrank(rewardsDistribuion);

        trufToken.transfer(address(trufStakingRewards), rewards);

        vm.expectEmit(true, true, true, true, address(trufStakingRewards));
        emit RewardAdded(rewards);
        trufStakingRewards.notifyRewardAmount(rewards);

        assertEq(trufStakingRewards.lastUpdateTime(), block.timestamp, "lastUpdateTime is invalid");
        assertEq(trufStakingRewards.periodFinish(), block.timestamp + 7 days, "periodFinish is invalid");
        assertEq(trufStakingRewards.rewardRate(), rewards / 7 days, "periodFinish is invalid");

        vm.stopPrank();
    }

    function testNotifyRewardAmount_BeforePeriodFinish() external {
        console.log("Notify rewards before pevious period end");

        uint256 firstRewards = 100e18;

        _notifyReward(firstRewards);

        uint256 rewards = 50e18;

        vm.warp(block.timestamp + 3 days);

        vm.startPrank(rewardsDistribuion);

        trufToken.transfer(address(trufStakingRewards), rewards);

        vm.expectEmit(true, true, true, true, address(trufStakingRewards));
        emit RewardAdded(rewards);
        trufStakingRewards.notifyRewardAmount(rewards);

        assertEq(trufStakingRewards.lastUpdateTime(), block.timestamp, "lastUpdateTime is invalid");
        assertEq(trufStakingRewards.periodFinish(), block.timestamp + 7 days, "periodFinish is invalid");

        assertEq(
            trufStakingRewards.rewardRate(),
            (firstRewards / 7 days * 4 days + rewards) / 7 days,
            "periodFinish is invalid"
        );

        vm.stopPrank();
    }

    function testNotifyRewardAmount_Revert_WhenRewardIsLowerThanBalance() external {
        console.log("Should revert if notified reward amount is lower than balance");

        uint256 rewards = 100e18;
        vm.startPrank(rewardsDistribuion);

        trufToken.transfer(address(trufStakingRewards), rewards);

        vm.expectRevert(abi.encodeWithSignature("InsufficientRewards()"));
        trufStakingRewards.notifyRewardAmount(101e18);

        vm.stopPrank();
    }

    function testSetRewardsDistribution() external {
        console.log("Set rewards distribution");
        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true, address(trufStakingRewards));
        emit RewardsDistributionUpdated(alice);

        trufStakingRewards.setRewardsDistribution(alice);

        assertEq(trufStakingRewards.rewardsDistribution(), alice, "RewardsDistribution is invalid");

        vm.stopPrank();
    }

    function testSetRewardsDistributionFailure() external {
        console.log("Should revert to set address(0) as rewardsDistribution");

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        trufStakingRewards.setRewardsDistribution(address(0));

        vm.stopPrank();

        console.log("Should revert when sender is not owner");
        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        trufStakingRewards.setRewardsDistribution(alice);

        vm.stopPrank();
    }

    function testSetOperator() external {
        console.log("Set operator");
        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true, address(trufStakingRewards));
        emit OperatorUpdated(alice);

        trufStakingRewards.setOperator(alice);

        assertEq(trufStakingRewards.operator(), alice, "Operator is invalid");

        vm.stopPrank();
    }

    function testSetOperatorFailure() external {
        console.log("Should revert to set address(0) as operator");

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        trufStakingRewards.setOperator(address(0));

        vm.stopPrank();

        console.log("Should revert when sender is not owner");
        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        trufStakingRewards.setOperator(alice);

        vm.stopPrank();
    }

    function _notifyReward(uint256 amount) internal {
        vm.startPrank(rewardsDistribuion);

        trufToken.transfer(address(trufStakingRewards), amount);
        trufStakingRewards.notifyRewardAmount(amount);

        vm.stopPrank();
    }

    function _stake(address user, uint256 amount) internal {
        vm.startPrank(operator);

        trufStakingRewards.stake(user, amount);

        vm.stopPrank();
    }

    function _withdraw(address user, uint256 amount) internal {
        vm.startPrank(operator);

        trufStakingRewards.withdraw(user, amount);

        vm.stopPrank();
    }

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event RewardsDistributionUpdated(address indexed rewardsDistribution);
    event OperatorUpdated(address indexed operator);
}
