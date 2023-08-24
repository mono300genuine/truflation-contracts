// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/TfiMembership.sol";
import "../src/libraries/Errors.sol";
import "../src/mock/MockERC20.sol";

contract TfiMembershipTest is Test {
    TfiMembership public tfiMembership;

    address public alice;
    address public bob;
    address public gov;
    MockERC20 public pToken;
    MockERC20 public usdt;
    MockERC20 public tfiToken;
    MockERC20 public lpToken;
    address public pOwner;

    function setUp() public {
        pToken = new MockERC20(18);
        usdt = new MockERC20(6);
        tfiToken = new MockERC20(18);
        lpToken = new MockERC20(18);

        alice = address(uint160(uint256(keccak256(abi.encodePacked("Alice")))));
        bob = address(uint160(uint256(keccak256(abi.encodePacked("Bob")))));
        pOwner = address(uint160(uint256(keccak256(abi.encodePacked("protocol owner")))));
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(pOwner, "pOwner");
    }

    function test_constructor_revertIfZeroAddress() external {
        console.log("Should revert if tfiToken is address(0)");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new TfiMembership(address(0), address(usdt), address(lpToken), address(usdt));

        console.log("Should revert if pairToken is address(0)");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new TfiMembership(address(tfiToken), address(0), address(usdt), address(usdt));

        console.log("Should revert if lpToken is address(0)");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new TfiMembership(address(tfiToken), address(usdt),address(0),  address(usdt));

        console.log("Should revert if lpToken is address(0)");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new TfiMembership(address(tfiToken), address(usdt), address(lpToken), address(0) );
    }
}
