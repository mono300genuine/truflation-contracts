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

    // function testSetUserVesting_AddFirstUserVesting() external {
    //     console.log("Add first user vesting");

    //     _setupVestingPlan();

    //     uint256 amount = 100e18;
    //     vm.startPrank(owner);
    //     vesting.setUserVesting(1, 0, alice, 0, amount);

    //     vm.expectEmit(true, true, true, true, address(vesting));
    //     emit VestingInfoSet(0, 0, TfiVesting.VestingInfo(initialReleasePct, initialReleasePeriod, cliff, period, unit));
    //     vesting.setVestingInfo(
    //         0, type(uint256).max, TfiVesting.VestingInfo(initialReleasePct, initialReleasePeriod, cliff, period, unit)
    //     );
    //     _validateVestingInfo(0, 0, initialReleasePct, initialReleasePeriod, cliff, period, unit);

    //     vm.stopPrank();
    // }

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
        string memory category,
        uint256 maxAllocation,
        uint256 allocated
    ) internal {
        (string memory _category, uint256 _maxAllocation, uint256 _allocated) = vesting.categories(categoryId);
        assertEq(_category, category, "Category name is invalid");
        assertEq(_maxAllocation, maxAllocation, "Max allocation is invalid");
        assertEq(_allocated, allocated, "Allocated amount is invalid");
    }
}
