// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../../src/token/TruflationToken.sol";
import "../mock/MockERC677Receiver.sol";

contract TruflationTokenTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value, bytes data);

    TruflationToken public trufToken;
    MockERC677Receiver public erc677Receiver;

    // Users
    address public alice;
    address public bob;

    string public name = "Truflation";
    string public symbol = "TRUF";
    uint8 public decimals = 18;
    uint256 public totalSupply = 1_000_000_000e18;

    function setUp() public {
        trufToken = new TruflationToken();

        alice = address(uint160(uint256(keccak256(abi.encodePacked("Alice")))));
        bob = address(uint160(uint256(keccak256(abi.encodePacked("Bob")))));

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");

        erc677Receiver = new MockERC677Receiver();

        trufToken.transfer(alice, 1e20);
    }

    function testConstructorSuccess() external {
        console.log("Check initial variables");
        assertEq(trufToken.name(), name, "Token name is invalid");
        assertEq(trufToken.symbol(), symbol, "Token symbol is invalid");
        assertEq(trufToken.decimals(), decimals, "Token decimals is invalid");
        assertEq(trufToken.totalSupply(), totalSupply, "Token supply is invalid");
    }

    function testTransferAndCallToContract() external {
        console.log("Test transferAndCall to contract");

        uint256 amount = 1e18;
        bytes memory data = "0x1234";

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true, address(trufToken));
        emit Transfer(alice, address(erc677Receiver), amount, data);

        trufToken.transferAndCall(address(erc677Receiver), amount, data);

        assertEq(trufToken.balanceOf(address(erc677Receiver)), amount, "Received balance is invalid");
        assertEq(erc677Receiver.sender(), alice, "Sender is invalid");
        assertEq(erc677Receiver.value(), amount, "Value is invalid");
        assertEq(erc677Receiver.data(), data, "Data is invalid");
        vm.stopPrank();
    }

    function testTransferAndCallToEoa() external {
        console.log("Test transferAndCall to EOA");

        uint256 amount = 1e18;
        bytes memory data = "0x1234";

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true, address(trufToken));
        emit Transfer(alice, bob, amount, data);

        trufToken.transferAndCall(bob, amount, data);

        assertEq(trufToken.balanceOf(address(bob)), amount, "Received balance is invalid");
        vm.stopPrank();
    }
}
