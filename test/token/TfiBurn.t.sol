// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../../src/token/TruflationToken.sol";
import "../../src/token/TfiBurn.sol";

contract TfiBurnTest is Test {
    event BurnedOldTfi(address indexed user, uint256 amount);

    TruflationToken public tfiToken;
    TfiBurn public tfiBurn;

    // Users
    address public alice;

    function setUp() public {
        alice = address(uint160(uint256(keccak256(abi.encodePacked("Alice")))));

        vm.label(alice, "Alice");

        tfiToken = new TruflationToken();
        tfiBurn = new TfiBurn(address(tfiToken));

        tfiToken.transfer(alice, 1e20);
    }

    function testConstructorSuccess() external {
        console.log("Check initial variables");
        assertEq(address(tfiBurn.oldTfi()), address(tfiToken), "Tfi token is invalid");
    }

    function testBurnOldTfi() external {
        vm.startPrank(alice);
        tfiToken.approve(address(tfiBurn), type(uint256).max);

        uint256 amount = 1e18;

        vm.expectEmit(true, true, true, true, address(tfiBurn));
        emit BurnedOldTfi(alice, amount);

        tfiBurn.burnOldTfi(amount);

        vm.stopPrank();

        assertEq(tfiToken.balanceOf(tfiBurn.BURN_ADDRESS()), amount, "Burned token should be sent to burn address");
        assertEq(tfiToken.balanceOf(alice), 1e20 - amount, "Burned token should be removed from user");
    }

    function testBurnOldTfiFailures() external {
        console.log("Revert if amount is 0");

        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));

        tfiBurn.burnOldTfi(0);

        vm.stopPrank();
    }
}
