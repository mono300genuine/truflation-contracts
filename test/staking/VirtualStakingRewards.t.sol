// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../../src/token/TruflationToken.sol";
import "../../src/token/VotingEscrowTfi.sol";
import "../../src/staking/VirtualStakingRewards.sol";

contract VirtualStakingRewardsTest is Test {
    TruflationToken public tfiToken;
    VirtualStakingRewards public tfiStakingRewards;

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
        tfiToken = new TruflationToken();
        tfiStakingRewards = new VirtualStakingRewards(rewardsDistribuion, address(tfiToken));
        tfiStakingRewards.setOperator(operator);
        tfiToken.transfer(rewardsDistribuion, tfiToken.totalSupply());

        vm.stopPrank();
    }

    function testConstructorSuccess() external {
        console.log("Check initial variables");
        assertEq(address(tfiStakingRewards.rewardsToken()), address(tfiToken), "Reward Token is invalid");
        assertEq(tfiStakingRewards.owner(), owner, "Owner is invalid");
        assertEq(tfiStakingRewards.rewardsDistribution(), rewardsDistribuion, "rewardsDistribuion is invalid");
        assertEq(tfiStakingRewards.totalSupply(), 0, "Initial supply is invalid");
    }

    function testConstructorFailure() external {
        console.log("Should revert if rewards token is address(0)");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new VirtualStakingRewards(rewardsDistribuion, address(0));

        console.log("Should revert if rewardsDistribution is address(0)");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new VirtualStakingRewards(address(0), address(tfiToken));
    }

    function testSetRewardsDuration() external {
        console.log("Set rewards duration");

        vm.startPrank(owner);

        uint256 newDuration = 14 days;

        vm.expectEmit(true, true, true, true, address(tfiStakingRewards));
        emit RewardsDurationUpdated(newDuration);

        tfiStakingRewards.setRewardsDuration(newDuration);

        assertEq(tfiStakingRewards.rewardsDuration(), newDuration, "RewardsDuration is invalid");

        vm.stopPrank();
    }

    function testSetRewardsDurationFailure() external {
        console.log("Should revert to set 0 as rewardsDuration");

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        tfiStakingRewards.setRewardsDuration(0);

        vm.stopPrank();

        console.log("Should revert when sender is not owner");
        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        tfiStakingRewards.setRewardsDuration(14 days);

        vm.stopPrank();

        _notifyReward(100e18);
        vm.warp(block.timestamp + 3 days);

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("RewardPeriodNotFinished()"));
        tfiStakingRewards.setRewardsDuration(14 days);
    }

    function testLastTimeRewardApplicable() external {
        console.log("Return block timestamp if reward period is not finished");

        uint256 rewardAmount = 100e18;
        _notifyReward(rewardAmount);

        vm.warp(block.timestamp + 3 days);

        assertEq(
            tfiStakingRewards.lastTimeRewardApplicable(),
            block.timestamp,
            "Return block timestamp if reward period is not finished"
        );

        vm.warp(block.timestamp + 5 days);

        assertEq(
            tfiStakingRewards.lastTimeRewardApplicable(),
            tfiStakingRewards.periodFinish(),
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
            tfiStakingRewards.rewardPerToken(),
            tfiStakingRewards.rewardPerTokenStored() + (1 days * rewardRate * 1e18 / totalSupply),
            "RewardPerToken is invalid"
        );

        console.log("Return rewardPerTokenStored if totalSupply is zero");
        _withdraw(alice, aliceAmount);
        _withdraw(bob, bobAmount);

        vm.warp(block.timestamp + 1 days);
        assertEq(
            tfiStakingRewards.rewardPerToken(), tfiStakingRewards.rewardPerTokenStored(), "RewardPerToken is invalid"
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
            tfiStakingRewards.earned(alice),
            (aliceAmount + aliceAmount2)
                * (tfiStakingRewards.rewardPerToken() - tfiStakingRewards.userRewardPerTokenPaid(alice)) / 1e18
                + tfiStakingRewards.rewards(alice),
            "Earned amount is invalid"
        );
    }

    function testGetRewardForDuration() external {
        console.log("Get reward for duration");

        uint256 rewardAmount = 100e18;
        _notifyReward(rewardAmount);

        uint256 rewardRate = rewardAmount / 7 days;
        assertEq(tfiStakingRewards.getRewardForDuration(), rewardRate * 7 days, "Reward for duration is invalid");
    }

    function testStake_FirstTime() external {
        console.log("Stake first time");

        uint256 amount = 10e18;

        vm.startPrank(operator);

        vm.expectEmit(true, true, true, true, address(tfiStakingRewards));
        emit Staked(alice, amount);

        tfiStakingRewards.stake(alice, amount);

        assertEq(tfiStakingRewards.totalSupply(), amount, "Total supply is invalid");
        assertEq(tfiStakingRewards.balanceOf(alice), amount, "Balance is invalid");

        vm.stopPrank();
    }

    function testStake_SecondTime() external {
        console.log("Stake second time");

        uint256 rewardAmount = 100e18;
        _notifyReward(rewardAmount);

        uint256 firstAmount = 10e18;
        uint256 secondAmount = 20e18;

        vm.startPrank(operator);

        tfiStakingRewards.stake(alice, firstAmount);

        vm.warp(block.timestamp + 3 days);

        vm.expectEmit(true, true, true, true, address(tfiStakingRewards));
        emit Staked(alice, secondAmount);

        tfiStakingRewards.stake(alice, secondAmount);

        // Validate supply and balance
        assertEq(tfiStakingRewards.totalSupply(), firstAmount + secondAmount, "Total supply is invalid");
        assertEq(tfiStakingRewards.balanceOf(alice), firstAmount + secondAmount, "Balance is invalid");

        // Validate rewards updates
        assertEq(tfiStakingRewards.lastUpdateTime(), block.timestamp, "Last updated time is invalid");
        assertEq(tfiStakingRewards.rewards(alice), tfiStakingRewards.earned(alice), "Reward was not updated");
        assertEq(
            tfiStakingRewards.userRewardPerTokenPaid(alice),
            tfiStakingRewards.rewardPerTokenStored(),
            "UserRewardPerTokenPaid was not updated"
        );

        vm.stopPrank();
    }

    function testStakeFailure() external {
        console.log("Should revert to stake for address(0)");

        vm.startPrank(operator);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        tfiStakingRewards.stake(address(0), 1e18);

        console.log("Should revert to stake for zero amount");
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        tfiStakingRewards.stake(alice, 0);

        vm.stopPrank();

        console.log("Should revert when sender is not operator");
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("Forbidden(address)", owner));
        tfiStakingRewards.stake(alice, 1e18);

        vm.stopPrank();
    }

    function testWithdraw() external {
        console.log("Withdraw");

        uint256 rewardAmount = 100e18;
        _notifyReward(rewardAmount);

        uint256 stakeAmount = 10e18;
        uint256 amount = 5e18;

        vm.startPrank(operator);

        tfiStakingRewards.stake(alice, stakeAmount);

        vm.warp(block.timestamp + 3 days);

        vm.expectEmit(true, true, true, true, address(tfiStakingRewards));
        emit Withdrawn(alice, amount);

        tfiStakingRewards.withdraw(alice, amount);

        // Validate supply and balance
        assertEq(tfiStakingRewards.totalSupply(), stakeAmount - amount, "Total supply is invalid");
        assertEq(tfiStakingRewards.balanceOf(alice), stakeAmount - amount, "Balance is invalid");

        // Validate rewards updates
        assertEq(tfiStakingRewards.lastUpdateTime(), block.timestamp, "Last updated time is invalid");
        assertEq(tfiStakingRewards.rewards(alice), tfiStakingRewards.earned(alice), "Reward was not updated");
        assertEq(
            tfiStakingRewards.userRewardPerTokenPaid(alice),
            tfiStakingRewards.rewardPerTokenStored(),
            "UserRewardPerTokenPaid was not updated"
        );

        vm.stopPrank();
    }

    function testWithdrawFailure() external {
        vm.startPrank(operator);
        console.log("Should revert to withdraw zero amount");
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        tfiStakingRewards.withdraw(alice, 0);

        vm.stopPrank();

        console.log("Should revert when sender is not operator");
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("Forbidden(address)", owner));
        tfiStakingRewards.withdraw(alice, 1e18);

        vm.stopPrank();
    }

    function testGetReward() external {
        console.log("Get reward");

        uint256 rewardAmount = 100e18;
        _notifyReward(rewardAmount);

        uint256 stakeAmount = 10e18;

        vm.startPrank(operator);

        tfiStakingRewards.stake(alice, stakeAmount);

        vm.warp(block.timestamp + 3 days);

        uint256 reward = tfiStakingRewards.earned(alice);
        vm.expectEmit(true, true, true, true, address(tfiStakingRewards));
        emit RewardPaid(alice, reward);

        tfiStakingRewards.getReward(alice);

        // Validate supply and balance
        assertEq(tfiStakingRewards.totalSupply(), stakeAmount, "Total supply is invalid");
        assertEq(tfiStakingRewards.balanceOf(alice), stakeAmount, "Balance is invalid");

        // Validate rewards updates
        assertEq(tfiStakingRewards.lastUpdateTime(), block.timestamp, "Last updated time is invalid");
        assertEq(tfiStakingRewards.rewards(alice), 0, "Reward was not updated");
        assertEq(
            tfiStakingRewards.userRewardPerTokenPaid(alice),
            tfiStakingRewards.rewardPerTokenStored(),
            "UserRewardPerTokenPaid was not updated"
        );

        assertEq(tfiToken.balanceOf(alice), reward, "Received reward is invalid");

        vm.stopPrank();
    }

    function testGetReward_DoNotRevert_WhenRewardIsZero() external {
        console.log("Do not revert when reward amount is zero");

        vm.startPrank(operator);

        tfiStakingRewards.getReward(alice);

        assertEq(tfiToken.balanceOf(alice), 0, "Reward should be zero");

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

        uint256 reward = tfiStakingRewards.earned(alice);

        tfiStakingRewards.exit(alice);

        // Validate supply and balance
        assertEq(tfiStakingRewards.totalSupply(), 0, "Total supply is invalid");
        assertEq(tfiStakingRewards.balanceOf(alice), 0, "Balance is invalid");

        // Validate rewards updates
        assertEq(tfiStakingRewards.lastUpdateTime(), block.timestamp, "Last updated time is invalid");
        assertEq(tfiStakingRewards.rewards(alice), 0, "Reward was not updated");
        assertEq(
            tfiStakingRewards.userRewardPerTokenPaid(alice),
            tfiStakingRewards.rewardPerTokenStored(),
            "UserRewardPerTokenPaid was not updated"
        );

        assertEq(tfiToken.balanceOf(alice), reward, "Received reward is invalid");

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

        uint256 reward = tfiStakingRewards.earned(alice);

        assertEq(tfiStakingRewards.rewards(alice), reward, "Reward was not updated");

        tfiStakingRewards.exit(alice);
        assertEq(tfiStakingRewards.rewards(alice), 0, "Reward was not updated");

        assertEq(tfiToken.balanceOf(alice), reward, "Received reward is invalid");
    }

    function testNotifyRewardAmount() external {
        console.log("Notify rewards");

        uint256 rewards = 100e18;
        vm.startPrank(rewardsDistribuion);

        tfiToken.transfer(address(tfiStakingRewards), rewards);

        vm.expectEmit(true, true, true, true, address(tfiStakingRewards));
        emit RewardAdded(rewards);
        tfiStakingRewards.notifyRewardAmount(rewards);

        assertEq(tfiStakingRewards.lastUpdateTime(), block.timestamp, "lastUpdateTime is invalid");
        assertEq(tfiStakingRewards.periodFinish(), block.timestamp + 7 days, "periodFinish is invalid");
        assertEq(tfiStakingRewards.rewardRate(), rewards / 7 days, "periodFinish is invalid");

        vm.stopPrank();
    }

    function testNotifyRewardAmount_BeforePeriodFinish() external {
        console.log("Notify rewards before pevious period end");

        uint256 firstRewards = 100e18;

        _notifyReward(firstRewards);

        uint256 rewards = 50e18;

        vm.warp(block.timestamp + 3 days);

        vm.startPrank(rewardsDistribuion);

        tfiToken.transfer(address(tfiStakingRewards), rewards);

        vm.expectEmit(true, true, true, true, address(tfiStakingRewards));
        emit RewardAdded(rewards);
        tfiStakingRewards.notifyRewardAmount(rewards);

        assertEq(tfiStakingRewards.lastUpdateTime(), block.timestamp, "lastUpdateTime is invalid");
        assertEq(tfiStakingRewards.periodFinish(), block.timestamp + 7 days, "periodFinish is invalid");

        assertEq(
            tfiStakingRewards.rewardRate(),
            (firstRewards / 7 days * 4 days + rewards) / 7 days,
            "periodFinish is invalid"
        );

        vm.stopPrank();
    }

    function testNotifyRewardAmount_Revert_WhenRewardIsLowerThanBalance() external {
        console.log("Should revert if notified reward amount is lower than balance");

        uint256 rewards = 100e18;
        vm.startPrank(rewardsDistribuion);

        tfiToken.transfer(address(tfiStakingRewards), rewards);

        vm.expectRevert(abi.encodeWithSignature("InsufficientRewards()"));
        tfiStakingRewards.notifyRewardAmount(101e18);

        vm.stopPrank();
    }

    function testSetRewardsDistribution() external {
        console.log("Set rewards distribution");
        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true, address(tfiStakingRewards));
        emit RewardsDistributionUpdated(alice);

        tfiStakingRewards.setRewardsDistribution(alice);

        assertEq(tfiStakingRewards.rewardsDistribution(), alice, "RewardsDistribution is invalid");

        vm.stopPrank();
    }

    function testSetRewardsDistributionFailure() external {
        console.log("Should revert to set address(0) as rewardsDistribution");

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        tfiStakingRewards.setRewardsDistribution(address(0));

        vm.stopPrank();

        console.log("Should revert when sender is not owner");
        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        tfiStakingRewards.setRewardsDistribution(alice);

        vm.stopPrank();
    }

    function testSetOperator() external {
        console.log("Set operator");
        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true, address(tfiStakingRewards));
        emit OperatorUpdated(alice);

        tfiStakingRewards.setOperator(alice);

        assertEq(tfiStakingRewards.operator(), alice, "Operator is invalid");

        vm.stopPrank();
    }

    function testSetOperatorFailure() external {
        console.log("Should revert to set address(0) as operator");

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        tfiStakingRewards.setOperator(address(0));

        vm.stopPrank();

        console.log("Should revert when sender is not owner");
        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        tfiStakingRewards.setOperator(alice);

        vm.stopPrank();
    }

    function _notifyReward(uint256 amount) internal {
        vm.startPrank(rewardsDistribuion);

        tfiToken.transfer(address(tfiStakingRewards), amount);
        tfiStakingRewards.notifyRewardAmount(amount);

        vm.stopPrank();
    }

    function _stake(address user, uint256 amount) internal {
        vm.startPrank(operator);

        tfiStakingRewards.stake(user, amount);

        vm.stopPrank();
    }

    function _withdraw(address user, uint256 amount) internal {
        vm.startPrank(operator);

        tfiStakingRewards.withdraw(user, amount);

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
