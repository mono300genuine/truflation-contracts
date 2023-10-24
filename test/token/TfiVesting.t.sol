// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../../src/token/TruflationToken.sol";
import "../../src/token/TfiVesting.sol";
import "../mock/MockERC677Receiver.sol";

contract TfiVestingTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value, bytes data);
    event TgeTimeSet(uint64 tgeTime);
    event VestingCategorySet(uint256 indexed id, string category, uint256 maxAllocation);
    event VestingInfoSet(uint256 indexed categoryId, uint256 indexed id, TfiVesting.VestingInfo info);
    event UserVestingSet(
        uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, uint256 amount, uint64 startTime
    );
    event MigrateUser(uint256 indexed categoryId, uint256 indexed vestingId, address prevUser, address newUser);
    event CancelVesting(uint256 indexed categoryId, uint256 indexed vestingId, address indexed user);
    event Claimed(uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, uint256 amount);
    event VeTfiSet(address indexed veTFI);
    event Locked(uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, uint256 amount);
    event Unlocked(uint256 indexed categoryId, uint256 indexed vestingId, address indexed user, uint256 amount);

    TruflationToken public tfiToken;
    TfiVesting public vesting;

    // Users
    address public alice;
    address public bob;
    address public owner;

    function setUp() public {
        alice = address(uint160(uint256(keccak256(abi.encodePacked("Alice")))));
        bob = address(uint160(uint256(keccak256(abi.encodePacked("Bob")))));
        owner = address(uint160(uint256(keccak256(abi.encodePacked("Owner")))));

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(owner, "Owner");

        vm.startPrank(owner);
        tfiToken = new TruflationToken();
        vesting = new TfiVesting(tfiToken);
        vm.stopPrank();

        vm.warp(1696816730);
    }

    function testConstructorSuccess() external {
        console.log("Check initial variables");
        assertEq(address(vesting.tfiToken()), address(tfiToken), "Tfi Token is invalid");
        assertEq(vesting.owner(), owner, "Owner is invalid");
    }

    function testConstructorFailure() external {
        console.log("Should revert if tfiToken is address(0)");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new TfiVesting(IERC20(address(0)));
    }

    function testSetVestingCategory_AddFirstCategory() external {
        console.log("Add first category");
        string memory category = "Preseed";
        uint256 maxAllocation = 1e20;

        vm.startPrank(owner);
        tfiToken.approve(address(vesting), type(uint256).max);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit VestingCategorySet(0, category, maxAllocation);

        vesting.setVestingCategory(type(uint256).max, category, maxAllocation);

        _validateCategory(0, category, maxAllocation, 0);
        assertEq(tfiToken.balanceOf(address(vesting)), maxAllocation, "Balance is invalid");

        vm.stopPrank();
    }

    function testSetVestingCategory_AddAnotherCategory() external {
        console.log("Add another category");
        string memory category = "Seed";
        uint256 maxAllocation = 1e15;

        vm.startPrank(owner);
        tfiToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", 1e20);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit VestingCategorySet(1, category, maxAllocation);
        vesting.setVestingCategory(type(uint256).max, category, maxAllocation);

        _validateCategory(1, category, maxAllocation, 0);
        assertEq(tfiToken.balanceOf(address(vesting)), maxAllocation + 1e20, "Balance is invalid");

        vm.stopPrank();
    }

    function testSetVestingCategory_IncreaseMaxAllocation_WhenNoAllocated() external {
        console.log("Increase max allocation when nothing allocated");
        uint256 maxAllocation = 15e14;

        vm.startPrank(owner);
        tfiToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", 1e20);
        vesting.setVestingCategory(type(uint256).max, "Seed", 1e15);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit VestingCategorySet(1, "Private", maxAllocation);
        vesting.setVestingCategory(1, "Private", maxAllocation);

        _validateCategory(1, "Private", maxAllocation, 0);
        assertEq(tfiToken.balanceOf(address(vesting)), maxAllocation + 1e20, "Balance is invalid");

        vm.stopPrank();
    }

    function testSetVestingCategory_IncreaseMaxAllocation_WhenSomeAllocated() external {
        console.log("Increase max allocation when some allocated");
        uint256 maxAllocation = 15e14;
        uint256 allocated = 1e14;

        vm.startPrank(owner);
        vesting.setTgeTime(uint64(block.timestamp) + 1 days);
        tfiToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", 1e20);
        vesting.setVestingCategory(type(uint256).max, "Seed", 1e15);
        vesting.setVestingInfo(1, type(uint256).max, TfiVesting.VestingInfo(0, 0, 0, 10 days, 7 days));
        vesting.setUserVesting(1, 0, alice, 0, allocated);
        _validateCategory(1, "Seed", 1e15, allocated);

        uint256 ownerTfiBalance = tfiToken.balanceOf(owner);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit VestingCategorySet(1, "Private", maxAllocation);
        vesting.setVestingCategory(1, "Private", maxAllocation);

        _validateCategory(1, "Private", maxAllocation, allocated);
        assertEq(tfiToken.balanceOf(address(vesting)), maxAllocation + 1e20, "Balance is invalid");
        assertEq(tfiToken.balanceOf(owner), ownerTfiBalance - (maxAllocation - 1e15), "Balance is invalid");

        vm.stopPrank();
    }

    function testSetVestingCategory_DecreaseMaxAllocation() external {
        console.log("Decrease max allocation");
        uint256 maxAllocation = 2e14;
        uint256 allocated = 1e14;

        vm.startPrank(owner);
        vesting.setTgeTime(uint64(block.timestamp) + 1 days);
        tfiToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", 1e20);
        vesting.setVestingCategory(type(uint256).max, "Seed", 1e15);
        vesting.setVestingInfo(1, type(uint256).max, TfiVesting.VestingInfo(0, 0, 0, 10 days, 7 days));
        vesting.setUserVesting(1, 0, alice, 0, allocated);
        _validateCategory(1, "Seed", 1e15, allocated);

        uint256 ownerTfiBalance = tfiToken.balanceOf(owner);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit VestingCategorySet(1, "Private", maxAllocation);
        vesting.setVestingCategory(1, "Private", maxAllocation);

        _validateCategory(1, "Private", maxAllocation, allocated);
        assertEq(tfiToken.balanceOf(address(vesting)), maxAllocation + 1e20, "Balance is invalid");
        assertEq(tfiToken.balanceOf(owner), ownerTfiBalance + (1e15 - maxAllocation), "Balance is invalid");

        vm.stopPrank();
    }

    function testSetVestingCategory_Revert_DecreaseMaxAllocationBelowAllocated() external {
        console.log("Should revert to decrease max allocation below allocated amount");
        uint256 maxAllocation = 2e14;
        uint256 allocated = 5e14;

        vm.startPrank(owner);
        vesting.setTgeTime(uint64(block.timestamp) + 1 days);
        tfiToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", 1e20);
        vesting.setVestingCategory(type(uint256).max, "Seed", 1e15);
        vesting.setVestingInfo(1, type(uint256).max, TfiVesting.VestingInfo(0, 0, 0, 10 days, 7 days));
        vesting.setUserVesting(1, 0, alice, 0, allocated);
        _validateCategory(1, "Seed", 1e15, allocated);

        vm.expectRevert(abi.encodeWithSignature("MaxAllocationExceed()"));
        vesting.setVestingCategory(1, "Private", maxAllocation);

        vm.stopPrank();
    }

    function testSetVestingCategory_Revert_WhenSenderIsNotOwner() external {
        console.log("Should revert when sender is not owner");

        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        vesting.setVestingCategory(type(uint256).max, "Preseed", 1e20);

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
        tfiToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", 1e20);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit VestingInfoSet(0, 0, TfiVesting.VestingInfo(initialReleasePct, initialReleasePeriod, cliff, period, unit));
        vesting.setVestingInfo(
            0, type(uint256).max, TfiVesting.VestingInfo(initialReleasePct, initialReleasePeriod, cliff, period, unit)
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
        tfiToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", 1e20);
        vesting.setVestingInfo(0, type(uint256).max, TfiVesting.VestingInfo(10, 10 days, 30 days, 180 days, 7 days));

        vm.expectEmit(true, true, true, true, address(vesting));
        emit VestingInfoSet(0, 0, TfiVesting.VestingInfo(initialReleasePct, initialReleasePeriod, cliff, period, unit));
        vesting.setVestingInfo(
            0, 0, TfiVesting.VestingInfo(initialReleasePct, initialReleasePeriod, cliff, period, unit)
        );
        _validateVestingInfo(0, 0, initialReleasePct, initialReleasePeriod, cliff, period, unit);

        vm.stopPrank();
    }

    function testSetVestingInfo_Revert_WhenSenderIsNotOwner() external {
        console.log("Should revert when sender is not owner");

        vm.startPrank(owner);
        tfiToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", 1e20);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        vesting.setVestingInfo(0, type(uint256).max, TfiVesting.VestingInfo(10, 10 days, 30 days, 180 days, 7 days));

        vm.stopPrank();
    }

    function testSetTgeTimeSuccess() external {
        console.log("Set TGE time");

        uint64 tgeTime = uint64(block.timestamp) + 1 days;
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true, address(vesting));
        emit TgeTimeSet(tgeTime);

        vesting.setTgeTime(tgeTime);

        assertEq(vesting.tgeTime(), tgeTime, "Tge time is invalid");

        vm.stopPrank();
    }

    function testSetTgeTimeFailure() external {
        uint64 tgeTime = uint64(block.timestamp) - 1 days;
        vm.startPrank(owner);
        console.log("Should revert to set tge time below block.timestamp");

        vm.expectRevert(abi.encodeWithSignature("InvalidTimestamp()"));
        vesting.setTgeTime(tgeTime);

        tgeTime = uint64(block.timestamp) + 1 days;
        vesting.setTgeTime(tgeTime);

        vm.warp(tgeTime + 1 days);

        vm.expectRevert(abi.encodeWithSignature("VestingStarted(uint64)", tgeTime));
        vesting.setTgeTime(tgeTime + 2 days);

        vm.stopPrank();
    }

    function testSetUserVesting_AddFirstUserVesting() external {
        console.log("Add first user vesting");

        _setupVestingPlan();

        uint256 amount = 100e18;
        uint64 tgeTime = uint64(block.timestamp) + 1 days;
        vm.startPrank(owner);
        vesting.setTgeTime(tgeTime);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit UserVestingSet(1, 0, alice, amount, tgeTime);

        vesting.setUserVesting(1, 0, alice, 0, amount);

        _validateUserVesting(1, 0, alice, amount, 0, 0, tgeTime);
        (,, uint256 allocated) = vesting.categories(1);
        assertEq(allocated, amount, "Allocated amount is invalid");

        vm.stopPrank();
    }

    function testSetUserVesting_Revert_WhenCategoryIdIsInvalid() external {
        console.log("Should revert to set user vesting when categoryId is invalid");

        _setupVestingPlan();

        uint256 amount = 100e18;
        uint64 tgeTime = uint64(block.timestamp) + 1 days;
        uint256 categoryId = 4;
        vm.startPrank(owner);
        vesting.setTgeTime(tgeTime);

        vm.expectRevert(abi.encodeWithSignature("InvalidVestingCategory(uint256)", categoryId));
        vesting.setUserVesting(categoryId, 0, alice, 0, amount);

        vm.stopPrank();
    }

    function testSetUserVesting_Revert_WhenVestingIdIsInvalid() external {
        console.log("Should revert to set user vesting when vestingId is invalid");

        _setupVestingPlan();

        uint256 amount = 100e18;
        uint64 tgeTime = uint64(block.timestamp) + 1 days;
        uint256 categoryId = 0;
        uint256 vestingId = 4;
        vm.startPrank(owner);
        vesting.setTgeTime(tgeTime);

        vm.expectRevert(abi.encodeWithSignature("InvalidVestingInfo(uint256,uint256)", categoryId, vestingId));
        vesting.setUserVesting(categoryId, vestingId, alice, 0, amount);

        vm.stopPrank();
    }

    function testSetUserVesting_Revert_WhenMaxAllocationExceed() external {
        console.log("Should revert to set user vesting when max allocation exceed");

        _setupVestingPlan();

        uint256 amount = 100e18;
        uint64 tgeTime = uint64(block.timestamp) + 1 days;
        uint256 categoryId = 0;
        uint256 vestingId = 0;

        (, uint256 maxAllocation,) = vesting.categories(categoryId);

        vm.startPrank(owner);
        vesting.setTgeTime(tgeTime);
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
        vesting.setTgeTime(uint64(block.timestamp) + 1 days);
        vesting.setUserVesting(categoryId, vestingId, alice, 0, amount);

        vm.warp(block.timestamp + 50 days);

        uint256 claimed = vesting.claimable(categoryId, vestingId, alice);
        assertNotEq(vesting.claimable(categoryId, vestingId, alice), 0, "Claimable amount should be non-zero");

        vm.stopPrank();

        vm.startPrank(alice);
        vesting.claim(categoryId, vestingId);

        assertEq(vesting.claimable(categoryId, vestingId, alice), 0, "Claimable amount should be zero");

        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidUserVesting()"));
        vesting.setUserVesting(categoryId, vestingId, alice, 0, claimed - 1);

        vm.stopPrank();
    }

    function testSetUserVesting_Revert_WhenTgeTimeAndStartTimeAreZero() external {
        console.log("Should revert to set user vesting when both start time and tge time are zero");

        _setupVestingPlan();

        uint256 amount = 100e18;
        uint256 categoryId = 0;
        uint256 vestingId = 0;

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidTimestamp()"));
        vesting.setUserVesting(categoryId, vestingId, alice, 0, amount);

        vm.stopPrank();
    }

    function testSetVeTfi() external {
        console.log("Set veTFI");

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true, address(vesting));
        emit VeTfiSet(alice);

        vesting.setVeTfi(alice);

        assertEq(address(vesting.veTFI()), alice, "veTFI is invalid");

        vm.stopPrank();
    }

    function testSetVeTfiFailure() external {
        vm.startPrank(owner);
        console.log("Should revert to set veTFI with zero address");

        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        vesting.setVeTfi(address(0));

        vm.stopPrank();
    }

    function testMulticall() external {
        console.log("Send multiple transactions through multicall");

        vm.startPrank(owner);
        tfiToken.approve(address(vesting), type(uint256).max);

        bytes[] memory payloads = new bytes[](2);
        payloads[0] =
            abi.encodeWithSignature("setVestingCategory(uint256,string,uint256)", type(uint256).max, "Preseed", 1e20);
        payloads[1] =
            abi.encodeWithSignature("setVestingCategory(uint256,string,uint256)", type(uint256).max, "Seed", 2e20);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit VestingCategorySet(0, "Preseed", 1e20);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit VestingCategorySet(1, "Seed", 2e20);

        vesting.multicall(payloads);

        _validateCategory(0, "Preseed", 1e20, 0);
        _validateCategory(1, "Seed", 2e20, 0);
        assertEq(tfiToken.balanceOf(address(vesting)), 3e20, "Balance is invalid");

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

        uint256 claimed = vesting.claimable(categoryId, vestingId, alice);
        assertNotEq(vesting.claimable(categoryId, vestingId, alice), 0, "Claimable amount should be non-zero");

        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true, address(vesting));
        emit Claimed(categoryId, vestingId, alice, claimed);

        vesting.claim(categoryId, vestingId);

        assertEq(vesting.claimable(categoryId, vestingId, alice), 0, "Claimable amount should be zero");
        assertEq(tfiToken.balanceOf(alice), claimed, "Claimed amount is incorrect");

        _validateUserVesting(categoryId, vestingId, alice, amount, claimed, 0, startTime);

        vm.stopPrank();
    }

    function testClaimFailure() external {
        console.log("Should revert to claim when there is no claimable amount");

        _setupVestingPlan();
        _setupExampleUserVestings();

        uint256 categoryId = 0;
        uint256 vestingId = 0;

        assertEq(vesting.claimable(categoryId, vestingId, alice), 0, "Claimable amount should be zero");

        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));

        vesting.claim(categoryId, vestingId);

        vm.stopPrank();
    }

    function _setupVestingPlan() internal {
        vm.startPrank(owner);

        tfiToken.approve(address(vesting), type(uint256).max);
        vesting.setVestingCategory(type(uint256).max, "Preseed", 171_400e18);
        vesting.setVestingCategory(type(uint256).max, "Seed", 391_000e18);
        vesting.setVestingCategory(type(uint256).max, "Private", 343_000e18);
        vesting.setVestingInfo(0, type(uint256).max, TfiVesting.VestingInfo(500, 0, 0, 24 * 30 days, 30 days));
        vesting.setVestingInfo(1, type(uint256).max, TfiVesting.VestingInfo(500, 0, 0, 24 * 30 days, 30 days));
        vesting.setVestingInfo(2, type(uint256).max, TfiVesting.VestingInfo(500, 0, 0, 24 * 30 days, 30 days));

        vm.stopPrank();
    }

    function _setupExampleUserVestings() internal {
        vm.startPrank(owner);

        vesting.setTgeTime(uint64(block.timestamp) + 1 days);
        vesting.setUserVesting(0, 0, alice, 0, 100e18);

        vm.stopPrank();
    }

    function _validateCategory(uint256 categoryId, string memory category, uint256 maxAllocation, uint256 allocated)
        internal
    {
        (string memory _category, uint256 _maxAllocation, uint256 _allocated) = vesting.categories(categoryId);
        assertEq(_category, category, "Category name is invalid");
        assertEq(_maxAllocation, maxAllocation, "Max allocation is invalid");
        assertEq(_allocated, allocated, "Allocated amount is invalid");
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
