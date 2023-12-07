// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../../src/token/TruflationTokenCCIP.sol";

contract TruflationTokenCCIPTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event CcipPoolSet(address indexed ccipPool);

    TruflationTokenCCIP public tfiToken;

    // Users
    address public owner;
    address public alice;
    address public ccipPool;

    string public name = "Truflation";
    string public symbol = "TFI";
    uint8 public decimals = 18;

    function setUp() public {
        owner = address(uint160(uint256(keccak256(abi.encodePacked("owner")))));
        alice = address(uint160(uint256(keccak256(abi.encodePacked("Alice")))));
        ccipPool = address(uint160(uint256(keccak256(abi.encodePacked("CcipPool")))));

        vm.label(owner, "Owner");
        vm.label(alice, "Alice");
        vm.label(ccipPool, "CcipPool");

        vm.startPrank(owner);
        tfiToken = new TruflationTokenCCIP();
        tfiToken.setCcipPool(ccipPool);
        vm.stopPrank();
    }

    function testConstructorSuccess() external {
        console.log("Check initial variables");
        assertEq(tfiToken.name(), name, "Token name is invalid");
        assertEq(tfiToken.symbol(), symbol, "Token symbol is invalid");
        assertEq(tfiToken.decimals(), decimals, "Token decimals is invalid");
        assertEq(tfiToken.totalSupply(), 0, "Token supply should be zero");
        assertEq(tfiToken.owner(), owner, "Token owner is invalid");
    }

    function testSetCcipPool() external {
        console.log("Should revert to set ccip pool by non-owner");
        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");

        tfiToken.setCcipPool(alice);
        vm.stopPrank();

        vm.startPrank(owner);
        console.log("Should revert to set address(0) as ccip pool");
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));

        tfiToken.setCcipPool(address(0));

        console.log("Set new CCIP pool by owner");

        vm.expectEmit(true, true, true, true, address(tfiToken));
        emit CcipPoolSet(alice);
        tfiToken.setCcipPool(alice);
        assertEq(tfiToken.ccipPool(), alice, "CCIP pool was not set");
        vm.stopPrank();
    }

    function testMint() external {
        console.log("Should revert to mint by non-ccipPool");
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("Forbidden(address)", alice));

        tfiToken.mint(alice, 100);
        vm.stopPrank();

        vm.startPrank(ccipPool);
        console.log("Mint new tokens by ccip pool");

        vm.expectEmit(true, true, true, true, address(tfiToken));
        emit Transfer(address(0), alice, 100);
        tfiToken.mint(alice, 100);

        assertEq(tfiToken.balanceOf(alice), 100, "New tokens should be minted");
        assertEq(tfiToken.totalSupply(), 100, "New tokens should be minted");
        vm.stopPrank();
    }

    function testBurn() external {
        vm.startPrank(ccipPool);
        tfiToken.mint(ccipPool, 1000);
        vm.stopPrank();

        console.log("Should revert to burn by non-ccipPool");
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("Forbidden(address)", alice));

        tfiToken.burn(100);
        vm.stopPrank();

        vm.startPrank(ccipPool);
        console.log("Burn by ccip pool");

        vm.expectEmit(true, true, true, true, address(tfiToken));
        emit Transfer(ccipPool, address(0), 100);
        tfiToken.burn(100);

        assertEq(tfiToken.balanceOf(ccipPool), 900, "Tokens should be burned");
        vm.stopPrank();
    }

    function testBurnFrom() external {
        vm.startPrank(ccipPool);
        tfiToken.mint(alice, 1000);
        vm.stopPrank();

        console.log("Should revert to burn by non-ccipPool");
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("Forbidden(address)", alice));

        tfiToken.burnFrom(alice, 100);
        vm.stopPrank();

        vm.startPrank(ccipPool);
        console.log("Burn by ccip pool");

        vm.expectEmit(true, true, true, true, address(tfiToken));
        emit Transfer(alice, address(0), 100);
        tfiToken.burnFrom(alice, 100);

        assertEq(tfiToken.balanceOf(alice), 900, "Tokens should be burned");
        vm.stopPrank();
    }
}
