// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../../src/token/TruflationToken.sol";
import "../../src/token/TrufVesting.sol";
import "../../src/token/VotingEscrowTruf.sol";
import "../../src/staking/VirtualStakingRewards.sol";

contract TrufVestingTest is Test {
    event VestingCategorySet(uint256 indexed id, string category, uint256 maxAllocation, bool adminClaimable);
    event EmissionScheduleSet(uint256 indexed categoryId, uint256[] emissions);
    event VestingInfoSet(uint256 indexed categoryId, uint256 indexed id, TrufVesting.VestingInfo info);
    event UserVestingSet(
        uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, uint256 amount, uint64 startTime
    );
    event MigrateUser(
        uint256 indexed categoryId, uint256 indexed vestingId, address prevUser, address newUser, uint256 newLockupId
    );
    event CancelVesting(
        uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, bool giveUnclaimed
    );
    event Claimed(uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, uint256 amount);
    event VeTrufSet(address indexed veTRUF);
    event Staked(
        uint256 indexed categoryId,
        uint256 indexed vestingId,
        address indexed user,
        uint256 amount,
        uint256 duration,
        uint256 lockupId
    );
    event ExtendedStaking(
        uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, uint256 duration
    );
    event Unstaked(uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, uint256 amount);

    TruflationToken public trufToken;
    TrufVesting public vesting;
    VotingEscrowTruf public veTRUF;
    VirtualStakingRewards public trufStakingRewards;

    // Users
    address public alice;
    address public bob;
    address public carol;
    address public owner;

    function setUp() public {
        alice = address(uint160(uint256(keccak256(abi.encodePacked("Alice")))));
        bob = address(uint160(uint256(keccak256(abi.encodePacked("Bob")))));
        carol = address(uint160(uint256(keccak256(abi.encodePacked("Carol")))));
        owner = address(uint160(uint256(keccak256(abi.encodePacked("Owner")))));

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(carol, "Carol");
        vm.label(owner, "Owner");

        vm.warp(1696816730);

        vm.startPrank(owner);
        trufToken = new TruflationToken();
        vesting = new TrufVesting(trufToken, uint64(block.timestamp) + 1 days);
        trufStakingRewards = new VirtualStakingRewards(owner, address(trufToken));
        veTRUF = new VotingEscrowTruf(address(trufToken), address(vesting), 1 hours, address(trufStakingRewards));
        trufStakingRewards.setOperator(address(veTRUF));
        vesting.setVeTruf(address(veTRUF));

        vm.stopPrank();
    }

    function testConstructorSuccess() external {
        console.log("Check initial variables");
        assertEq(address(vesting.trufToken()), address(trufToken), "TRUF Token is invalid");
        assertEq(vesting.owner(), owner, "Owner is invalid");
    }

    function testConstructorFailure() external {
        console.log("Should revert if trufToken is address(0)");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new TrufVesting(IERC20(address(0)), uint64(block.timestamp) + 1 days);

        console.log("Should revert if tge time is less than current time");
        vm.expectRevert(abi.encodeWithSignature("InvalidTimestamp()"));
        new TrufVesting(trufToken, uint64(block.timestamp) - 1);
    }

    function testSetVestingCategory_AddFirstCategory() external {
        console.log("Add first category");
        string memory category = "Preseed";
        uint256 maxAllocation = 1e20;
        bool adminClaimable = true;

        vm.startPrank(owner);
        trufToken.approve(address(vesting), type(uint256).max);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit VestingCategorySet(0, category, maxAllocation, adminClaimable);

        vesting.setVestingCategory(type(uint256).max, category, maxAllocation, adminClaimable);

        _validateCategory(0, category, maxAllocation, 0, adminClaimable, 0);
        assertEq(trufToken.balanceOf(address(vesting)), maxAllocation, "Balance is invalid");

        vm.stopPrank();
    }

    function testSetVestingCategory_AddAnotherCategory() external {
        console.log("Add another category");
        string memory category = "Seed";
        uint256 maxAllocation = 1e15;
        bool adminClaimable = false;

        vm.startPrank(owner);
        trufToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", 1e20, false);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit VestingCategorySet(1, category, maxAllocation, adminClaimable);
        vesting.setVestingCategory(type(uint256).max, category, maxAllocation, adminClaimable);

        _validateCategory(1, category, maxAllocation, 0, adminClaimable, 0);
        assertEq(trufToken.balanceOf(address(vesting)), maxAllocation + 1e20, "Balance is invalid");

        vm.stopPrank();
    }

    function testSetVestingCategory_IncreaseMaxAllocation_WhenNoAllocated() external {
        console.log("Increase max allocation when nothing allocated");
        uint256 maxAllocation = 15e14;
        bool adminClaimable = false;

        vm.startPrank(owner);
        trufToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", 1e20, false);
        vesting.setVestingCategory(type(uint256).max, "Seed", 1e15, false);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit VestingCategorySet(1, "Private", maxAllocation, adminClaimable);
        vesting.setVestingCategory(1, "Private", maxAllocation, adminClaimable);

        _validateCategory(1, "Private", maxAllocation, 0, adminClaimable, 0);
        assertEq(trufToken.balanceOf(address(vesting)), maxAllocation + 1e20, "Balance is invalid");

        vm.stopPrank();
    }

    function testSetVestingCategory_IncreaseMaxAllocation_WhenSomeAllocated() external {
        console.log("Increase max allocation when some allocated");
        uint256 maxAllocation = 15e14;
        uint256 allocated = 1e14;
        bool adminClaimable = false;

        vm.startPrank(owner);

        trufToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", 1e20, false);
        vesting.setVestingCategory(type(uint256).max, "Seed", 1e15, false);
        vesting.setVestingInfo(1, type(uint256).max, TrufVesting.VestingInfo(0, 0, 0, 10 days, 7 days));
        vesting.setUserVesting(1, 0, alice, 0, allocated);
        _validateCategory(1, "Seed", 1e15, allocated, false, 0);

        uint256 ownerTrufBalance = trufToken.balanceOf(owner);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit VestingCategorySet(1, "Private", maxAllocation, adminClaimable);
        vesting.setVestingCategory(1, "Private", maxAllocation, adminClaimable);

        _validateCategory(1, "Private", maxAllocation, allocated, adminClaimable, 0);
        assertEq(trufToken.balanceOf(address(vesting)), maxAllocation + 1e20, "Balance is invalid");
        assertEq(trufToken.balanceOf(owner), ownerTrufBalance - (maxAllocation - 1e15), "Balance is invalid");

        vm.stopPrank();
    }

    function testSetVestingCategory_DecreaseMaxAllocation() external {
        console.log("Decrease max allocation");
        uint256 maxAllocation = 2e14;
        uint256 allocated = 1e14;
        bool adminClaimable = true;

        vm.startPrank(owner);

        trufToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", 1e20, false);
        vesting.setVestingCategory(type(uint256).max, "Seed", 1e15, false);
        vesting.setVestingInfo(1, type(uint256).max, TrufVesting.VestingInfo(0, 0, 0, 10 days, 7 days));
        vesting.setUserVesting(1, 0, alice, 0, allocated);
        _validateCategory(1, "Seed", 1e15, allocated, false, 0);

        uint256 ownerTrufBalance = trufToken.balanceOf(owner);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit VestingCategorySet(1, "Private", maxAllocation, adminClaimable);
        vesting.setVestingCategory(1, "Private", maxAllocation, adminClaimable);

        _validateCategory(1, "Private", maxAllocation, allocated, adminClaimable, 0);
        assertEq(trufToken.balanceOf(address(vesting)), maxAllocation + 1e20, "Balance is invalid");
        assertEq(trufToken.balanceOf(owner), ownerTrufBalance + (1e15 - maxAllocation), "Balance is invalid");

        vm.stopPrank();
    }

    function testSetVestingCategory_Revert_DecreaseMaxAllocationBelowAllocated() external {
        console.log("Should revert to decrease max allocation below allocated amount");
        uint256 maxAllocation = 2e14;
        uint256 allocated = 5e14;

        vm.startPrank(owner);

        trufToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", 1e20, false);
        vesting.setVestingCategory(type(uint256).max, "Seed", 1e15, false);
        vesting.setVestingInfo(1, type(uint256).max, TrufVesting.VestingInfo(0, 0, 0, 10 days, 7 days));
        vesting.setUserVesting(1, 0, alice, 0, allocated);
        _validateCategory(1, "Seed", 1e15, allocated, false, 0);

        vm.expectRevert(abi.encodeWithSignature("MaxAllocationExceed()"));
        vesting.setVestingCategory(1, "Private", maxAllocation, false);

        vm.stopPrank();
    }

    function testSetVestingCategory_Revert_WhenSenderIsNotOwner() external {
        console.log("Should revert when sender is not owner");

        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        vesting.setVestingCategory(type(uint256).max, "Preseed", 1e20, false);

        vm.stopPrank();
    }

    function testSetVestingCategory_Revert_WhenMaxAllocationIsZero() external {
        console.log("Should revert when max allocation is zero");

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        vesting.setVestingCategory(type(uint256).max, "Preseed", 0, false);

        vm.stopPrank();
    }

    function testSetVestingCategory_AfterTge() external {
        console.log("Should revert when sender is not owner");

        uint64 tgeTime = vesting.tgeTime();

        vm.warp(tgeTime + 1);

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("VestingStarted(uint64)", tgeTime));
        vesting.setVestingCategory(type(uint256).max, "Preseed", 1e20, false);

        vm.stopPrank();
    }

    function testSetEmissionSchedule() external {
        console.log("Set Emission schedule");

        uint256 maxAllocation = 1e20;

        vm.startPrank(owner);
        trufToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", maxAllocation, false);

        uint256[] memory emissions = new uint256[](5);
        emissions[0] = 0;
        emissions[1] = 1e18;
        emissions[2] = 2e18;
        emissions[3] = 3e18;
        emissions[4] = 1e20;

        vm.expectEmit(true, true, true, true, address(vesting));
        emit EmissionScheduleSet(0, emissions);
        vesting.setEmissionSchedule(0, emissions);
        _validateEmissionSchedule(0, emissions);

        vm.stopPrank();
    }

    function testSetEmissionSchedule_Reset() external {
        console.log("Re-set Emission schedule");

        uint256 maxAllocation = 1e20;

        vm.startPrank(owner);
        trufToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", maxAllocation, false);

        uint256[] memory emissions = new uint256[](5);
        emissions[0] = 0;
        emissions[1] = 1e18;
        emissions[2] = 2e18;
        emissions[3] = 3e18;
        emissions[4] = 1e20;

        vesting.setEmissionSchedule(0, emissions);

        emissions[0] = 1e19;
        emissions[1] = 4e19;
        emissions[2] = 8e19;
        emissions[3] = 9e19;

        vm.expectEmit(true, true, true, true, address(vesting));
        emit EmissionScheduleSet(0, emissions);
        vesting.setEmissionSchedule(0, emissions);
        _validateEmissionSchedule(0, emissions);

        vm.stopPrank();
    }

    function testSetEmissionSchedule_Revert_WhenSenderIsNotOwner() external {
        console.log("Should revert when sender is not owner");

        uint256 maxAllocation = 1e20;

        vm.startPrank(owner);
        trufToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", maxAllocation, false);

        vm.stopPrank();

        vm.startPrank(alice);

        uint256[] memory emissions = new uint256[](5);
        emissions[0] = 0;
        emissions[1] = 1e18;
        emissions[2] = 2e18;
        emissions[3] = 3e18;
        emissions[4] = 1e20;

        vm.expectRevert("Ownable: caller is not the owner");
        vesting.setEmissionSchedule(0, emissions);

        vm.stopPrank();
    }

    function testSetEmissionSchedule_Revert_WhenLengthIsZero() external {
        console.log("Should revert when emission schedule length is zero");

        uint256 maxAllocation = 1e20;

        vm.startPrank(owner);
        trufToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", maxAllocation, false);

        uint256[] memory emissions;

        vm.expectRevert(abi.encodeWithSignature("InvalidEmissions()"));
        vesting.setEmissionSchedule(0, emissions);

        vm.stopPrank();
    }

    function testSetEmissionSchedule_Revert_WhenLastItemIsNotSameAsMaxAllocation() external {
        console.log("Should revert when last emission is not same as max allocation");

        uint256 maxAllocation = 1e20;

        vm.startPrank(owner);
        trufToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", maxAllocation, false);

        uint256[] memory emissions = new uint256[](5);
        emissions[0] = 0;
        emissions[1] = 1e18;
        emissions[2] = 2e18;
        emissions[3] = 3e18;
        emissions[4] = maxAllocation - 1;

        vm.expectRevert(abi.encodeWithSignature("InvalidEmissions()"));
        vesting.setEmissionSchedule(0, emissions);

        vm.stopPrank();
    }

    function testSetVestingInfo_AddFirstVestingInfo() external {
        console.log("Add first vesting info");

        uint64 initialReleasePct = 500;
        uint64 initialReleasePeriod = 30 days;
        uint64 cliff = 60 days;
        uint64 period = 360 days;
        uint64 unit = 30 days;

        vm.startPrank(owner);
        trufToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", 1e20, false);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit VestingInfoSet(0, 0, TrufVesting.VestingInfo(initialReleasePct, initialReleasePeriod, cliff, period, unit));
        vesting.setVestingInfo(
            0, type(uint256).max, TrufVesting.VestingInfo(initialReleasePct, initialReleasePeriod, cliff, period, unit)
        );
        _validateVestingInfo(0, 0, initialReleasePct, initialReleasePeriod, cliff, period, unit);

        vm.stopPrank();
    }

    function testSetVestingInfo_ModifyExistingVestingInfo() external {
        console.log("Add first vesting info");

        uint64 initialReleasePct = 500;
        uint64 initialReleasePeriod = 30 days;
        uint64 cliff = 60 days;
        uint64 period = 360 days;
        uint64 unit = 30 days;

        vm.startPrank(owner);
        trufToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", 1e20, false);
        vesting.setVestingInfo(0, type(uint256).max, TrufVesting.VestingInfo(10, 10 days, 30 days, 180 days, 7 days));

        vm.expectEmit(true, true, true, true, address(vesting));
        emit VestingInfoSet(0, 0, TrufVesting.VestingInfo(initialReleasePct, initialReleasePeriod, cliff, period, unit));
        vesting.setVestingInfo(
            0, 0, TrufVesting.VestingInfo(initialReleasePct, initialReleasePeriod, cliff, period, unit)
        );
        _validateVestingInfo(0, 0, initialReleasePct, initialReleasePeriod, cliff, period, unit);

        vm.stopPrank();
    }

    function testSetVestingInfo_Revert_WhenSenderIsNotOwner() external {
        console.log("Should revert when sender is not owner");

        vm.startPrank(owner);
        trufToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", 1e20, false);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        vesting.setVestingInfo(0, type(uint256).max, TrufVesting.VestingInfo(10, 10 days, 30 days, 180 days, 7 days));

        vm.stopPrank();
    }

    function testSetUserVesting_AddFirstUserVesting() external {
        console.log("Add first user vesting");

        _setupVestingPlan();

        uint256 amount = 100e18;
        uint64 tgeTime = vesting.tgeTime();
        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit UserVestingSet(1, 0, alice, amount, tgeTime);

        vesting.setUserVesting(1, 0, alice, 0, amount);

        _validateUserVesting(1, 0, alice, amount, 0, 0, tgeTime);
        (,, uint256 allocated,,) = vesting.categories(1);
        assertEq(allocated, amount, "Allocated amount is invalid");

        vm.stopPrank();
    }

    function testSetUserVesting_Revert_WhenCategoryIdIsInvalid() external {
        console.log("Should revert to set user vesting when categoryId is invalid");

        _setupVestingPlan();

        uint256 amount = 100e18;
        uint256 categoryId = 4;
        vm.startPrank(owner);

        vm.expectRevert(abi.encodeWithSignature("InvalidVestingCategory(uint256)", categoryId));
        vesting.setUserVesting(categoryId, 0, alice, 0, amount);

        vm.stopPrank();
    }

    function testSetUserVesting_Revert_WhenVestingIdIsInvalid() external {
        console.log("Should revert to set user vesting when vestingId is invalid");

        _setupVestingPlan();

        uint256 amount = 100e18;
        uint256 categoryId = 0;
        uint256 vestingId = 4;
        vm.startPrank(owner);

        vm.expectRevert(abi.encodeWithSignature("InvalidVestingInfo(uint256,uint256)", categoryId, vestingId));
        vesting.setUserVesting(categoryId, vestingId, alice, 0, amount);

        vm.stopPrank();
    }

    function testSetUserVesting_Revert_WhenMaxAllocationExceed() external {
        console.log("Should revert to set user vesting when max allocation exceed");

        _setupVestingPlan();

        uint256 amount = 100e18;
        uint256 categoryId = 0;
        uint256 vestingId = 0;

        (, uint256 maxAllocation,,,) = vesting.categories(categoryId);

        vm.startPrank(owner);
        vesting.setUserVesting(categoryId, vestingId, alice, 0, amount);

        vm.expectRevert(abi.encodeWithSignature("MaxAllocationExceed()"));
        vesting.setUserVesting(categoryId, vestingId, bob, 0, maxAllocation - amount + 1);

        vm.stopPrank();
    }

    function testSetUserVesting_Revert_WhenNewAmountIsLowerThanClaimedAndLocked() external {
        console.log("Should revert to reset user vesting amount when it is lower than claimed and locked amount");

        _setupVestingPlan();

        uint256 amount = 100e18;
        uint256 categoryId = 0;
        uint256 vestingId = 0;

        vm.startPrank(owner);

        vesting.setUserVesting(categoryId, vestingId, alice, 0, amount);

        vm.warp(block.timestamp + 50 days);

        uint256 claimed = vesting.claimable(categoryId, vestingId, alice);
        assertNotEq(vesting.claimable(categoryId, vestingId, alice), 0, "Claimable amount should be non-zero");

        vm.stopPrank();

        vm.startPrank(alice);
        vesting.claim(alice, categoryId, vestingId, claimed);

        assertEq(vesting.claimable(categoryId, vestingId, alice), 0, "Claimable amount should be zero");

        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidUserVesting()"));
        vesting.setUserVesting(categoryId, vestingId, alice, 0, claimed - 1);

        vm.stopPrank();
    }

    function testSetUserVesting_Revert_WhenStartTimeIsBeforeTgeTime() external {
        console.log("Should revert to set user vesting when start time is before tge time");

        _setupVestingPlan();

        uint256 amount = 100e18;
        uint256 categoryId = 0;
        uint256 vestingId = 0;

        uint64 tgeTime = vesting.tgeTime();

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidTimestamp()"));
        vesting.setUserVesting(categoryId, vestingId, alice, tgeTime - 1, amount);

        vm.stopPrank();
    }

    function testSetUserVesting_Revert_WhenSenderIsNotOwner() external {
        console.log("Should revert to set user vesting when msg.sender is not owner");

        _setupVestingPlan();

        uint256 amount = 100e18;
        uint256 categoryId = 0;
        uint256 vestingId = 0;

        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        vesting.setUserVesting(categoryId, vestingId, alice, 0, amount);

        vm.stopPrank();
    }

    function testSetUserVesting_Revert_WhenAmountIsZero() external {
        console.log("Should revert to set user vesting when amount is zero");

        _setupVestingPlan();

        uint256 categoryId = 0;
        uint256 vestingId = 0;

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        vesting.setUserVesting(categoryId, vestingId, alice, 0, 0);

        vm.stopPrank();
    }

    function testSetVeTruf() external {
        console.log("Set veTRUF");

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true, address(vesting));
        emit VeTrufSet(alice);

        vesting.setVeTruf(alice);

        assertEq(address(vesting.veTRUF()), alice, "veTRUF is invalid");

        vm.stopPrank();
    }

    function testSetVeTrufFailure() external {
        vm.startPrank(owner);
        console.log("Should revert to set veTRUF with zero address");

        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        vesting.setVeTruf(address(0));

        vm.stopPrank();
    }

    function testMulticall() external {
        console.log("Send multiple transactions through multicall");

        vm.startPrank(owner);
        trufToken.approve(address(vesting), type(uint256).max);

        bytes[] memory payloads = new bytes[](2);
        payloads[0] = abi.encodeWithSignature(
            "setVestingCategory(uint256,string,uint256,bool)", type(uint256).max, "Preseed", 1e20, false
        );
        payloads[1] = abi.encodeWithSignature(
            "setVestingCategory(uint256,string,uint256,bool)", type(uint256).max, "Seed", 2e20, true
        );

        vm.expectEmit(true, true, true, true, address(vesting));
        emit VestingCategorySet(0, "Preseed", 1e20, false);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit VestingCategorySet(1, "Seed", 2e20, true);

        vesting.multicall(payloads);

        _validateCategory(0, "Preseed", 1e20, 0, false, 0);
        _validateCategory(1, "Seed", 2e20, 0, true, 0);
        assertEq(trufToken.balanceOf(address(vesting)), 3e20, "Balance is invalid");

        vm.stopPrank();
    }

    function testClaim() external {
        console.log("Claim available amount");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 0;
        uint256 vestingId = 0;

        (uint256 amount,,, uint64 startTime) = vesting.userVestings(categoryId, vestingId, alice);

        vm.warp(block.timestamp + 50 days);

        uint256 claimable = vesting.claimable(categoryId, vestingId, alice);
        uint256 claimAmount = claimable - 10;
        assertNotEq(vesting.claimable(categoryId, vestingId, alice), 0, "Claimable amount should be non-zero");

        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit Claimed(categoryId, vestingId, alice, claimAmount);

        vesting.claim(alice, categoryId, vestingId, claimAmount);

        assertEq(vesting.claimable(categoryId, vestingId, alice), 10, "Claimable amount is invalid");
        assertEq(trufToken.balanceOf(alice), claimAmount, "Claimed amount is incorrect");

        _validateUserVesting(categoryId, vestingId, alice, amount, claimAmount, 0, startTime);

        vm.stopPrank();
    }

    function testClaim_By_Admin() external {
        console.log("Claim available amount by admin");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 3;
        uint256 vestingId = 0;

        (uint256 amount,,, uint64 startTime) = vesting.userVestings(categoryId, vestingId, carol);

        vm.warp(block.timestamp + 50 days);

        uint256 claimable = vesting.claimable(categoryId, vestingId, carol);
        uint256 claimAmount = claimable - 10;
        assertNotEq(vesting.claimable(categoryId, vestingId, carol), 0, "Claimable amount should be non-zero");

        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit Claimed(categoryId, vestingId, carol, claimAmount);

        vesting.claim(carol, categoryId, vestingId, claimAmount);

        assertEq(vesting.claimable(categoryId, vestingId, carol), 10, "Claimable amount is invalid");
        assertEq(trufToken.balanceOf(carol), claimAmount, "Claimed amount is incorrect");

        _validateUserVesting(categoryId, vestingId, carol, amount, claimAmount, 0, startTime);

        vm.stopPrank();
    }

    function testClaimFailure() external {
        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 0;
        uint256 vestingId = 0;

        assertEq(vesting.claimable(categoryId, vestingId, alice), 0, "Claimable amount should be zero");

        vm.startPrank(alice);

        console.log("Should revert to claim when there is no claimable amount");
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));

        vesting.claim(alice, categoryId, vestingId, 0);
        vm.stopPrank();

        vm.startPrank(bob);
        console.log("Should revert to claim if msg.sender is not user for non-admin-claimable");
        (,,, bool _adminClaimable,) = vesting.categories(categoryId);
        assertEq(_adminClaimable, false, "Not non-admin claimable");

        vm.expectRevert(abi.encodeWithSignature("Forbidden(address)", bob));

        vesting.claim(alice, categoryId, vestingId, 1);

        console.log("Should revert to claim if msg.sender is not user or owner for admin-claimable");
        (,,, _adminClaimable,) = vesting.categories(3);
        assertEq(_adminClaimable, true, "Not admin claimable");

        vm.expectRevert(abi.encodeWithSignature("Forbidden(address)", bob));

        vesting.claim(carol, 3, vestingId, 1);

        vm.stopPrank();

        vm.startPrank(alice);

        console.log("Should revert to claim when claim amount exceed claimable amount");
        vm.expectRevert(abi.encodeWithSignature("ClaimAmountExceed()"));

        vesting.claim(alice, categoryId, vestingId, 1);

        vm.stopPrank();
    }

    function testGetEmission_Returns_ZeroBeforeTGE() external {
        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 1;
        (, uint256 maxAllocation,,,) = vesting.categories(categoryId);

        vm.startPrank(owner);

        uint256[] memory emissions = new uint256[](5);
        emissions[0] = maxAllocation / 5;
        emissions[1] = maxAllocation / 5 * 2;
        emissions[2] = maxAllocation / 5 * 3;
        emissions[3] = maxAllocation / 5 * 4;
        emissions[4] = maxAllocation;

        vesting.setEmissionSchedule(categoryId, emissions);

        vm.stopPrank();

        uint64 tgeTime = vesting.tgeTime();
        vm.warp(tgeTime - 1);

        assertEq(vesting.getEmission(categoryId), 0, "Emission should be zero");
    }

    function testGetEmission_Returns_MaxAllocationIfNoEmissionSchedule() external {
        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 1;
        (, uint256 maxAllocation,,,) = vesting.categories(categoryId);

        uint64 tgeTime = vesting.tgeTime();
        vm.warp(tgeTime + 100);

        assertEq(vesting.getEmission(categoryId), maxAllocation, "Emission should be max allocation");
    }

    function testGetEmission_Returns_MaxAllocationAfterEndOfEmissionSchedule() external {
        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 1;
        (, uint256 maxAllocation,,,) = vesting.categories(categoryId);

        vm.startPrank(owner);

        uint256[] memory emissions = new uint256[](5);
        emissions[0] = maxAllocation / 5;
        emissions[1] = maxAllocation / 5 * 2;
        emissions[2] = maxAllocation / 5 * 3;
        emissions[3] = maxAllocation / 5 * 4;
        emissions[4] = maxAllocation;

        vesting.setEmissionSchedule(categoryId, emissions);

        vm.stopPrank();

        uint64 tgeTime = vesting.tgeTime();
        vm.warp(tgeTime + 5 * 30 days + 1);

        assertEq(vesting.getEmission(categoryId), maxAllocation, "Emission should be max allocation");
    }

    function testGetEmission_FirstMonth() external {
        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 1;
        (, uint256 maxAllocation,,,) = vesting.categories(categoryId);

        vm.startPrank(owner);

        uint256[] memory emissions = new uint256[](5);
        emissions[0] = maxAllocation / 5;
        emissions[1] = maxAllocation / 5 * 2;
        emissions[2] = maxAllocation / 5 * 3;
        emissions[3] = maxAllocation / 5 * 4;
        emissions[4] = maxAllocation;

        vesting.setEmissionSchedule(categoryId, emissions);

        vm.stopPrank();

        uint64 tgeTime = vesting.tgeTime();

        uint256 elapsed = 10 days;

        vm.warp(tgeTime + elapsed);

        assertEq(vesting.getEmission(categoryId), emissions[0] * 10 days / 30 days, "Invalid emission");
    }

    function testGetEmission_AfterFirstMonth() external {
        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 1;
        (, uint256 maxAllocation,,,) = vesting.categories(categoryId);

        vm.startPrank(owner);

        uint256[] memory emissions = new uint256[](5);
        emissions[0] = maxAllocation / 5;
        emissions[1] = maxAllocation / 5 * 2;
        emissions[2] = maxAllocation / 5 * 3;
        emissions[3] = maxAllocation / 5 * 4;
        emissions[4] = maxAllocation;

        vesting.setEmissionSchedule(categoryId, emissions);

        vm.stopPrank();

        uint64 tgeTime = vesting.tgeTime();

        uint256 elapsed = 10 days + 60 days;

        vm.warp(tgeTime + elapsed);

        assertEq(
            vesting.getEmission(categoryId),
            (emissions[2] - emissions[1]) * 10 days / 30 days + emissions[1],
            "Invalid emission"
        );
    }

    function testGetEmission_Returns_MaxAllocationIfEmissionIsHigher() external {
        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 1;
        (, uint256 maxAllocation,,,) = vesting.categories(categoryId);

        vm.startPrank(owner);

        uint256[] memory emissions = new uint256[](5);
        emissions[0] = maxAllocation / 5;
        emissions[1] = maxAllocation / 5 * 2;
        emissions[2] = maxAllocation / 5 * 3;
        emissions[3] = maxAllocation / 5 * 4;
        emissions[4] = maxAllocation;

        vesting.setEmissionSchedule(categoryId, emissions);

        uint256 newMaxAllocation = emissions[3] - 100;
        vesting.setVestingCategory(categoryId, "Preseed", newMaxAllocation, false);

        vm.stopPrank();

        uint64 tgeTime = vesting.tgeTime();

        uint256 elapsed = 10 days + 120 days;

        vm.warp(tgeTime + elapsed);

        assertEq(vesting.getEmission(categoryId), newMaxAllocation, "Invalid emission");
    }

    function testStake() external {
        console.log("Stake vesting to veTRUF");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 0;
        uint256 vestingId = 0;
        uint256 stakeAmount = 10e18;
        uint256 duration = 30 days;

        (uint256 amount,,, uint64 startTime) = vesting.userVestings(categoryId, vestingId, alice);

        uint256 trufBalanceBefore = trufToken.balanceOf(address(vesting));

        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit Staked(categoryId, vestingId, alice, stakeAmount, duration, 1);

        vesting.stake(categoryId, vestingId, stakeAmount, duration);

        assertEq(trufToken.balanceOf(address(veTRUF)), stakeAmount, "Staked amount is invalid");
        assertEq(trufToken.balanceOf(address(vesting)), trufBalanceBefore - stakeAmount, "Remaining balance is invalid");

        (uint128 lockupAmount,,,, bool lockupIsVesting) = veTRUF.lockups(alice, 0);

        assertEq(lockupAmount, stakeAmount, "Lockup amount is invalid");
        assertEq(lockupIsVesting, true, "Lockup vesting flag is invalid");

        _validateUserVesting(categoryId, vestingId, alice, amount, 0, stakeAmount, startTime);
        assertEq(vesting.lockupIds(categoryId, vestingId, alice), 1, "Lockup id is invalid");

        vm.stopPrank();
    }

    function testStake_Revert_WhenAmountIsZero() external {
        console.log("Revert to stake vesting when amount is zero");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 0;
        uint256 vestingId = 0;
        uint256 duration = 30 days;

        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        vesting.stake(categoryId, vestingId, 0, duration);

        vm.stopPrank();
    }

    function testStake_Revert_WhenLockExists() external {
        console.log("Revert to stake vesting when lock already exists");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 0;
        uint256 vestingId = 0;
        uint256 stakeAmount = 100e18;
        uint256 duration = 30 days;

        vm.startPrank(alice);

        vesting.stake(categoryId, vestingId, stakeAmount, duration);

        vm.expectRevert(abi.encodeWithSignature("LockExist()"));
        vesting.stake(categoryId, vestingId, 100, duration);

        vm.stopPrank();
    }

    function testStake_Revert_WhenAmountIsGreaterThanRemaining() external {
        console.log("Revert to stake vesting when amount is greater than remaining vesting amount");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 0;
        uint256 vestingId = 0;
        uint256 duration = 30 days;

        vm.warp(block.timestamp + 50 days);

        vm.startPrank(alice);

        uint256 claimed = vesting.claimable(categoryId, vestingId, alice);

        vesting.claim(alice, categoryId, vestingId, claimed);

        (uint256 amount,,,) = vesting.userVestings(categoryId, vestingId, alice);

        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));

        vesting.stake(categoryId, vestingId, amount - claimed + 1, duration);

        vm.stopPrank();
    }

    function testExtendStaking() external {
        console.log("Extend staking duration");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 0;
        uint256 vestingId = 0;
        uint256 stakeAmount = 10e18;
        uint256 duration = 30 days;
        uint256 extendDuration = 50 days;

        (uint256 amount,,, uint64 startTime) = vesting.userVestings(categoryId, vestingId, alice);

        uint256 trufBalanceBefore = trufToken.balanceOf(address(vesting));

        vm.startPrank(alice);

        vesting.stake(categoryId, vestingId, stakeAmount, duration);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit ExtendedStaking(categoryId, vestingId, alice, extendDuration);

        vesting.extendStaking(categoryId, vestingId, extendDuration);

        assertEq(trufToken.balanceOf(address(veTRUF)), stakeAmount, "Staked amount is invalid");
        assertEq(trufToken.balanceOf(address(vesting)), trufBalanceBefore - stakeAmount, "Remaining balance is invalid");

        (uint128 lockupAmount,,,, bool lockupIsVesting) = veTRUF.lockups(alice, 0);

        assertEq(lockupAmount, stakeAmount, "Lockup amount is invalid");
        assertEq(lockupIsVesting, true, "Lockup vesting flag is invalid");

        _validateUserVesting(categoryId, vestingId, alice, amount, 0, stakeAmount, startTime);
        assertEq(vesting.lockupIds(categoryId, vestingId, alice), 1, "Lockup id is invalid");

        vm.stopPrank();
    }

    function testExtendStaking_Revert_WhenLockDoesNotExists() external {
        console.log("Revert to extend staking when lock does not exist");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 0;
        uint256 vestingId = 0;

        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSignature("LockDoesNotExist()"));
        vesting.extendStaking(categoryId, vestingId, 30 days);

        vm.stopPrank();
    }

    function testUnstake() external {
        console.log("Unstake from veTRUF");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 0;
        uint256 vestingId = 0;
        uint256 stakeAmount = 10e18;
        uint256 duration = 30 days;

        (uint256 amount,,, uint64 startTime) = vesting.userVestings(categoryId, vestingId, alice);

        vm.startPrank(alice);

        vesting.stake(categoryId, vestingId, stakeAmount, duration);

        uint256 trufBalanceBefore = trufToken.balanceOf(address(vesting));

        vm.warp(block.timestamp + duration + 1);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit Unstaked(categoryId, vestingId, alice, stakeAmount);

        vesting.unstake(categoryId, vestingId);

        assertEq(trufToken.balanceOf(address(veTRUF)), 0, "Staked amount is invalid");
        assertEq(trufToken.balanceOf(address(vesting)), trufBalanceBefore + stakeAmount, "Remaining balance is invalid");

        (uint128 lockupAmount,,,, bool lockupIsVesting) = veTRUF.lockups(alice, 0);

        assertEq(lockupAmount, 0, "Lockup should was not deleted");
        assertEq(lockupIsVesting, false, "Lockup should was not deleted");

        _validateUserVesting(categoryId, vestingId, alice, amount, 0, 0, startTime);
        assertEq(vesting.lockupIds(categoryId, vestingId, alice), 0, "Lockup id is invalid");

        vm.stopPrank();
    }

    function testUnstake_Revert_WhenLockDoesNotExist() external {
        console.log("Revert to unstake when lock does not exist");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 0;
        uint256 vestingId = 0;

        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSignature("LockDoesNotExist()"));
        vesting.unstake(categoryId, vestingId);

        vm.stopPrank();
    }

    function testMigrateUser_WhenNoLock() external {
        console.log("Migrate vesting when lock does not exist");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 0;
        uint256 vestingId = 0;

        vm.warp(block.timestamp + 50 days);

        vm.startPrank(alice);

        uint256 claimAmount = vesting.claimable(categoryId, vestingId, alice);
        vesting.claim(alice, categoryId, vestingId, claimAmount);

        (uint256 amount, uint256 claimed,, uint64 startTime) = vesting.userVestings(categoryId, vestingId, alice);
        assertNotEq(claimed, 0, "Claimed amount should be non-zero");

        vm.warp(block.timestamp + 30 days);
        uint256 claimable = vesting.claimable(categoryId, vestingId, alice);
        assertNotEq(claimable, 0, "Claimable amount should be non-zero");

        vm.stopPrank();

        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit MigrateUser(categoryId, vestingId, alice, carol, 0);

        vesting.migrateUser(categoryId, vestingId, alice, carol);

        assertEq(vesting.claimable(categoryId, vestingId, alice), 0, "Claimable amount for prev user should be zero");
        assertEq(
            vesting.claimable(categoryId, vestingId, carol),
            claimable,
            "Claimable amount for new user should be migrated"
        );

        _validateUserVesting(categoryId, vestingId, alice, 0, 0, 0, 0);
        _validateUserVesting(categoryId, vestingId, carol, amount, claimed, 0, startTime);

        vm.stopPrank();
    }

    function testMigrateUser_WhenLocked() external {
        console.log("Migrate vesting when some tokens have been locked");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 0;
        uint256 vestingId = 0;
        uint256 stakeAmount = 10e18;
        uint256 duration = 30 days;

        vm.warp(block.timestamp + 50 days);

        vm.startPrank(alice);

        vesting.stake(categoryId, vestingId, stakeAmount, duration);
        uint256 claimAmount = vesting.claimable(categoryId, vestingId, alice);
        vesting.claim(alice, categoryId, vestingId, claimAmount);

        (uint256 amount, uint256 claimed,, uint64 startTime) = vesting.userVestings(categoryId, vestingId, alice);
        assertNotEq(claimed, 0, "Claimed amount should be non-zero");

        vm.warp(block.timestamp + 30 days);
        uint256 claimable = vesting.claimable(categoryId, vestingId, alice);
        assertNotEq(claimable, 0, "Claimable amount should be non-zero");

        vm.stopPrank();

        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit MigrateUser(categoryId, vestingId, alice, carol, 1);

        vesting.migrateUser(categoryId, vestingId, alice, carol);

        assertEq(vesting.claimable(categoryId, vestingId, alice), 0, "Claimable amount for prev user should be zero");
        assertEq(
            vesting.claimable(categoryId, vestingId, carol),
            claimable,
            "Claimable amount for new user should be migrated"
        );
        assertEq(vesting.lockupIds(categoryId, vestingId, alice), 0, "Prev user lockup id should be zero");
        assertEq(vesting.lockupIds(categoryId, vestingId, carol), 1, "Lockup id should be migrated");

        _validateUserVesting(categoryId, vestingId, alice, 0, 0, 0, 0);
        _validateUserVesting(categoryId, vestingId, carol, amount, claimed, stakeAmount, startTime);

        vm.stopPrank();
    }

    function testMigrateUser_Revert_WhenSenderIsNotOwner() external {
        console.log("Revert when msg.sender is not owner");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 0;
        uint256 vestingId = 0;

        vm.startPrank(alice);

        vm.expectRevert("Ownable: caller is not the owner");
        vesting.migrateUser(categoryId, vestingId, alice, carol);

        vm.stopPrank();
    }

    function testMigrateUser_Revert_WhenNewUserHasVesting() external {
        console.log("Revert when new user has vesting in same category and vesting id");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 0;
        uint256 vestingId = 0;

        vm.startPrank(owner);

        vm.expectRevert(
            abi.encodeWithSignature("UserVestingAlreadySet(uint256,uint256,address)", categoryId, vestingId, bob)
        );
        vesting.migrateUser(categoryId, vestingId, alice, bob);

        vm.stopPrank();
    }

    function testMigrateUser_Revert_WhenPrevUserDoesNotHaveVesting() external {
        console.log("Revert when user does not have vesting");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 0;
        uint256 vestingId = 0;

        vm.startPrank(owner);

        vm.expectRevert(
            abi.encodeWithSignature("UserVestingDoesNotExists(uint256,uint256,address)", categoryId, vestingId, carol)
        );
        vesting.migrateUser(categoryId, vestingId, carol, owner);

        vm.stopPrank();
    }

    function testCancelVesting_ByTakingClaimableTokens() external {
        console.log("Cancel vesting and remove uncalimed amount");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 0;
        uint256 vestingId = 0;

        vm.warp(block.timestamp + 50 days);

        vm.startPrank(alice);

        uint256 claimAmount = vesting.claimable(categoryId, vestingId, alice);
        vesting.claim(alice, categoryId, vestingId, claimAmount);

        (uint256 amount, uint256 claimed,,) = vesting.userVestings(categoryId, vestingId, alice);
        assertNotEq(claimed, 0, "Claimed amount should be non-zero");

        vm.warp(block.timestamp + 30 days);
        uint256 claimable = vesting.claimable(categoryId, vestingId, alice);
        assertNotEq(claimable, 0, "Claimable amount should be non-zero");

        vm.stopPrank();

        vm.startPrank(owner);

        uint256 vestingBalanceBefore = trufToken.balanceOf(address(vesting));

        (string memory _category, uint256 _maxAllocation, uint256 _allocated, bool _adminClaimable,) =
            vesting.categories(categoryId);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit CancelVesting(categoryId, vestingId, alice, false);

        vesting.cancelVesting(categoryId, vestingId, alice, false);

        assertEq(vesting.claimable(categoryId, vestingId, alice), 0, "Claimable amount for prev user should be zero");

        _validateUserVesting(categoryId, vestingId, alice, 0, 0, 0, 0);
        _validateCategory(
            categoryId, _category, _maxAllocation, _allocated + claimed - amount, _adminClaimable, claimAmount
        );
        assertEq(trufToken.balanceOf(address(vesting)), vestingBalanceBefore, "Token does not move after cancel");

        vm.stopPrank();
    }

    function testCancelVesting_ByGivingClaimableTokens() external {
        console.log("Cancel vesting and give current vested amount to user");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 0;
        uint256 vestingId = 0;

        vm.warp(block.timestamp + 50 days);

        vm.startPrank(alice);

        uint256 claimAmount = vesting.claimable(categoryId, vestingId, alice);
        vesting.claim(alice, categoryId, vestingId, claimAmount);

        (uint256 amount, uint256 claimed,,) = vesting.userVestings(categoryId, vestingId, alice);
        assertNotEq(claimed, 0, "Claimed amount should be non-zero");

        vm.warp(block.timestamp + 30 days);
        uint256 claimable = vesting.claimable(categoryId, vestingId, alice);
        assertNotEq(claimable, 0, "Claimable amount should be non-zero");

        vm.stopPrank();

        vm.startPrank(owner);

        uint256 vestingBalanceBefore = trufToken.balanceOf(address(vesting));

        (string memory _category, uint256 _maxAllocation, uint256 _allocated, bool _adminClaimable,) =
            vesting.categories(categoryId);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit CancelVesting(categoryId, vestingId, alice, true);

        vesting.cancelVesting(categoryId, vestingId, alice, true);

        assertEq(vesting.claimable(categoryId, vestingId, alice), 0, "Claimable amount for prev user should be zero");

        _validateUserVesting(categoryId, vestingId, alice, 0, 0, 0, 0);
        _validateCategory(
            categoryId,
            _category,
            _maxAllocation,
            _allocated + claimed + claimable - amount,
            _adminClaimable,
            claimable + claimed
        );
        assertEq(
            trufToken.balanceOf(address(vesting)), vestingBalanceBefore - claimable, "Token does not move after cancel"
        );
        assertEq(trufToken.balanceOf(alice), claimed + claimable, "User should receive unclaimed tokens");

        vm.stopPrank();
    }

    function testCancelVesting_WhenLocked() external {
        console.log("Cancel vesting when some tokens have been locked");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 0;
        uint256 vestingId = 0;
        uint256 stakeAmount = 10e18;
        uint256 duration = 30 days;

        vm.warp(block.timestamp + 50 days);

        vm.startPrank(alice);

        uint256 claimAmount = vesting.claimable(categoryId, vestingId, alice);
        vesting.claim(alice, categoryId, vestingId, claimAmount);
        vesting.stake(categoryId, vestingId, stakeAmount, duration);

        (uint256 amount, uint256 claimed,,) = vesting.userVestings(categoryId, vestingId, alice);
        assertNotEq(claimed, 0, "Claimed amount should be non-zero");

        vm.warp(block.timestamp + 30 days);
        uint256 claimable = vesting.claimable(categoryId, vestingId, alice);
        assertNotEq(claimable, 0, "Claimable amount should be non-zero");

        vm.stopPrank();

        vm.startPrank(owner);

        uint256 vestingBalanceBefore = trufToken.balanceOf(address(vesting));

        (string memory _category, uint256 _maxAllocation, uint256 _allocated, bool _adminClaimable,) =
            vesting.categories(categoryId);

        assertEq(vesting.lockupIds(categoryId, vestingId, alice), 1, "Lockup id is invalid");

        vm.expectEmit(true, true, true, true, address(vesting));
        emit CancelVesting(categoryId, vestingId, alice, false);

        vesting.cancelVesting(categoryId, vestingId, alice, false);

        assertEq(vesting.claimable(categoryId, vestingId, alice), 0, "Claimable amount for prev user should be zero");

        _validateUserVesting(categoryId, vestingId, alice, 0, 0, 0, 0);
        _validateCategory(
            categoryId, _category, _maxAllocation, _allocated + claimed - amount, _adminClaimable, claimAmount
        );
        assertEq(
            trufToken.balanceOf(address(vesting)),
            vestingBalanceBefore + stakeAmount,
            "Token does not move after cancel"
        );
        assertEq(vesting.lockupIds(categoryId, vestingId, alice), 0, "Lockup id should be zero");

        vm.stopPrank();
    }

    function testCancelVesting_Revert_WhenSenderIsNotOwner() external {
        console.log("Revert when msg.sender is not owner");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 0;
        uint256 vestingId = 0;

        vm.startPrank(alice);

        vm.expectRevert("Ownable: caller is not the owner");
        vesting.migrateUser(categoryId, vestingId, alice, carol);

        vm.stopPrank();
    }

    function testCancelVesting_Revert_WhenNewUserHasVesting() external {
        console.log("Revert when new user has vesting in same category and vesting id");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 0;
        uint256 vestingId = 0;

        vm.startPrank(owner);

        vm.expectRevert(
            abi.encodeWithSignature("UserVestingAlreadySet(uint256,uint256,address)", categoryId, vestingId, bob)
        );
        vesting.migrateUser(categoryId, vestingId, alice, bob);

        vm.stopPrank();
    }

    function testCancelVesting_Revert_WhenPrevUserDoesNotHaveVesting() external {
        console.log("Revert when user does not have vesting");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 0;
        uint256 vestingId = 0;

        vm.startPrank(owner);

        vm.expectRevert(
            abi.encodeWithSignature("UserVestingDoesNotExists(uint256,uint256,address)", categoryId, vestingId, carol)
        );
        vesting.migrateUser(categoryId, vestingId, carol, owner);

        vm.stopPrank();
    }

    function testClaimableBeforeInitialRelease() external {
        console.log("Return 0 if current time is before initial release time");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 2;
        uint256 vestingId = 0;

        uint64 tgeTime = vesting.tgeTime();

        (, uint64 _initialReleasePeriod,,,) = vesting.vestingInfos(categoryId, vestingId);

        vm.warp(tgeTime + _initialReleasePeriod - 1);

        assertEq(vesting.claimable(categoryId, vestingId, alice), 0, "Claimable amount should be zero");
    }

    function testClaimableAfterInitialReleaseBeforeCliff() external {
        console.log("Return initial release amount if current time is after initial release time and before cliff time");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 2;
        uint256 vestingId = 0;

        (uint256 amount,,,) = vesting.userVestings(categoryId, vestingId, alice);

        uint64 tgeTime = vesting.tgeTime();

        (uint64 _initialReleasePct, uint64 _initialReleasePeriod, uint64 _cliff,,) =
            vesting.vestingInfos(categoryId, vestingId);

        vm.warp(tgeTime + _initialReleasePeriod + _cliff - 1);

        assertEq(
            vesting.claimable(categoryId, vestingId, alice),
            amount * _initialReleasePct / vesting.DENOMINATOR(),
            "Claimable amount should be initial release amount"
        );
    }

    function testClaimableAfterCliff() external {
        console.log("Return vested amount if current time is after cliff");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 2;
        uint256 vestingId = 0;

        (uint256 amount,,,) = vesting.userVestings(categoryId, vestingId, alice);

        uint64 tgeTime = vesting.tgeTime();

        (uint64 _initialReleasePct, uint64 _initialReleasePeriod, uint64 _cliff, uint64 _period, uint64 _unit) =
            vesting.vestingInfos(categoryId, vestingId);

        vm.warp(tgeTime + _initialReleasePeriod + _cliff + _unit * 3 + _unit / 2);

        uint256 initialRelease = amount * _initialReleasePct / vesting.DENOMINATOR();
        uint256 vestedAmount = (amount - initialRelease) * (_unit * 3) / _period + initialRelease;

        assertEq(vesting.claimable(categoryId, vestingId, alice), vestedAmount, "Claimable amount is incorrect");
    }

    function _setupVestingPlan() internal {
        vm.startPrank(owner);

        trufToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", 171_400e18, false);
        vesting.setVestingCategory(type(uint256).max, "Seed", 391_000e18, false);
        vesting.setVestingCategory(type(uint256).max, "Private", 343_000e18, false);
        vesting.setVestingCategory(type(uint256).max, "Liquidity", 120_000e18, true);
        vesting.setVestingInfo(0, type(uint256).max, TrufVesting.VestingInfo(500, 0, 0, 24 * 30 days, 30 days));
        vesting.setVestingInfo(1, type(uint256).max, TrufVesting.VestingInfo(500, 0, 0, 24 * 30 days, 30 days));
        vesting.setVestingInfo(
            2, type(uint256).max, TrufVesting.VestingInfo(500, 10 days, 20 days, 24 * 30 days, 30 days)
        );
        vesting.setVestingInfo(3, type(uint256).max, TrufVesting.VestingInfo(500, 0, 0, 24 * 30 days, 30 days));

        vm.stopPrank();
    }

    function _setupExampleUserVestings() internal {
        vm.startPrank(owner);

        vesting.setUserVesting(0, 0, alice, 0, 100e18);
        vesting.setUserVesting(0, 0, bob, 0, 200e18);
        vesting.setUserVesting(3, 0, carol, 0, 200e18);
        vesting.setUserVesting(2, 0, alice, 0, 200e18);

        vm.stopPrank();
    }

    function _validateCategory(
        uint256 categoryId,
        string memory category,
        uint256 maxAllocation,
        uint256 allocated,
        bool adminClaimable,
        uint256 totalClaimed
    ) internal {
        (
            string memory _category,
            uint256 _maxAllocation,
            uint256 _allocated,
            bool _adminClaimable,
            uint256 _totalClaimed
        ) = vesting.categories(categoryId);
        assertEq(_category, category, "Category name is invalid");
        assertEq(_maxAllocation, maxAllocation, "Max allocation is invalid");
        assertEq(_allocated, allocated, "Allocated amount is invalid");
        assertEq(_adminClaimable, adminClaimable, "Admin claimable flag is invalid");
        assertEq(_totalClaimed, totalClaimed, "Total claimed amount is invalid");
    }

    function _validateEmissionSchedule(uint256 categoryId, uint256[] memory emissions) internal {
        uint256[] memory _emissions = vesting.getEmissionSchedule(categoryId);

        assertEq(_emissions.length, emissions.length, "Emission is invalid");
        for (uint256 i = 0; i < emissions.length; i += 1) {
            assertEq(_emissions[i], emissions[i], "Emission is invalid");
        }
    }

    function _validateVestingInfo(
        uint256 categoryId,
        uint256 vestingId,
        uint64 initialReleasePct,
        uint64 initialReleasePeriod,
        uint64 cliff,
        uint64 period,
        uint64 unit
    ) internal {
        (uint64 _initialReleasePct, uint64 _initialReleasePeriod, uint64 _cliff, uint64 _period, uint64 _unit) =
            vesting.vestingInfos(categoryId, vestingId);
        assertEq(_initialReleasePct, initialReleasePct, "Initial release percentage is invalid");
        assertEq(_initialReleasePeriod, initialReleasePeriod, "Initial release period is invalid");
        assertEq(_cliff, cliff, "Cliff period is invalid");
        assertEq(_period, period, "Total period is invalid");
        assertEq(_unit, unit, "Release unit is invalid");
    }

    function _validateUserVesting(
        uint256 categoryId,
        uint256 vestingId,
        address user,
        uint256 amount,
        uint256 claimed,
        uint256 locked,
        uint64 startTime
    ) internal {
        (uint256 _amount, uint256 _claimed, uint256 _locked, uint64 _startTime) =
            vesting.userVestings(categoryId, vestingId, user);
        assertEq(_amount, amount, "Amount is invalid");
        assertEq(_claimed, claimed, "Claimed amount is invalid");
        assertEq(_locked, locked, "Locked amount is invalid");
        assertEq(_startTime, startTime, "Start timestamp is invalid");
    }
}
