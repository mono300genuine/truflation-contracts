// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../../src/token/TruflationTokenCCIP.sol";

contract TruflationTokenCCIPTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event CcipPoolSet(address indexed ccipPool);

    TruflationTokenCCIP public trufToken;

    // Users
    address public owner;
    address public alice;
    address public ccipPool;

    string public name = "Truflation";
    string public symbol = "TRUF";
    uint8 public decimals = 18;

    function setUp() public {
        owner = address(uint160(uint256(keccak256(abi.encodePacked("owner")))));
        alice = address(uint160(uint256(keccak256(abi.encodePacked("Alice")))));
        ccipPool = address(uint160(uint256(keccak256(abi.encodePacked("CcipPool")))));

        vm.label(owner, "Owner");
        vm.label(alice, "Alice");
        vm.label(ccipPool, "CcipPool");

        vm.startPrank(owner);
        trufToken = new TruflationTokenCCIP();
        trufToken.setCcipPool(ccipPool);
        vm.stopPrank();
    }

    function testConstructorSuccess() external {
        console.log("Check initial variables");
        assertEq(trufToken.name(), name, "Token name is invalid");
        assertEq(trufToken.symbol(), symbol, "Token symbol is invalid");
        assertEq(trufToken.decimals(), decimals, "Token decimals is invalid");
        assertEq(trufToken.totalSupply(), 0, "Token supply should be zero");
        assertEq(trufToken.owner(), owner, "Token owner is invalid");
    }

    function testSetCcipPool() external {
        console.log("Should revert to set ccip pool by non-owner");
        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");

        trufToken.setCcipPool(alice);
        vm.stopPrank();

        vm.startPrank(owner);
        console.log("Should revert to set address(0) as ccip pool");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));

        trufToken.setCcipPool(address(0));

        console.log("Set new CCIP pool by owner");

        vm.expectEmit(true, true, true, true, address(trufToken));
        emit CcipPoolSet(alice);
        trufToken.setCcipPool(alice);
        assertEq(trufToken.ccipPool(), alice, "CCIP pool was not set");
        vm.stopPrank();
    }

    function testMint() external {
        console.log("Should revert to mint by non-ccipPool");
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("Forbidden(address)", alice));

        trufToken.mint(alice, 100);
        vm.stopPrank();

        vm.startPrank(ccipPool);
        console.log("Mint new tokens by ccip pool");

        vm.expectEmit(true, true, true, true, address(trufToken));
        emit Transfer(address(0), alice, 100);
        trufToken.mint(alice, 100);

        assertEq(trufToken.balanceOf(alice), 100, "New tokens should be minted");
        assertEq(trufToken.totalSupply(), 100, "New tokens should be minted");
        vm.stopPrank();
    }

    function testBurn() external {
        vm.startPrank(ccipPool);
        trufToken.mint(ccipPool, 1000);
        vm.stopPrank();

        console.log("Should revert to burn by non-ccipPool");
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("Forbidden(address)", alice));

        trufToken.burn(100);
        vm.stopPrank();

        vm.startPrank(ccipPool);
        console.log("Burn by ccip pool");

        vm.expectEmit(true, true, true, true, address(trufToken));
        emit Transfer(ccipPool, address(0), 100);
        trufToken.burn(100);

        assertEq(trufToken.balanceOf(ccipPool), 900, "Tokens should be burned");
        vm.stopPrank();
    }
}
