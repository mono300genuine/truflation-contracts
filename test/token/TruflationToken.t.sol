// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../../src/token/TruflationToken.sol";
import "../mock/MockERC677Receiver.sol";

contract TruflationTokenTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value, bytes data);

    TruflationToken public tfiToken;
    MockERC677Receiver public erc677Receiver;

    // Users
    address public alice;
    address public bob;

    string public name = "Truflation";
    string public symbol = "TFI";
    uint8 public decimals = 18;
    uint256 public totalSupply = 100_000_000 * 1e18;

    function setUp() public {
        tfiToken = new TruflationToken();

        alice = address(uint160(uint256(keccak256(abi.encodePacked("Alice")))));
        bob = address(uint160(uint256(keccak256(abi.encodePacked("Bob")))));

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");

        erc677Receiver = new MockERC677Receiver();

        tfiToken.transfer(alice, 1e20);
    }

    function testConstructorSuccess() external {
        console.log("Check initial variables");
        assertEq(tfiToken.name(), name, "Token name is invalid");
        assertEq(tfiToken.symbol(), symbol, "Token symbol is invalid");
        assertEq(tfiToken.decimals(), decimals, "Token decimals is invalid");
        assertEq(tfiToken.totalSupply(), totalSupply, "Token supply is invalid");
    }

    function testTransferAndCallToContract() external {
        console.log("Test transferAndCall to contract");

        uint256 amount = 1e18;
        bytes memory data = "0x1234";

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true, address(tfiToken));
        emit Transfer(alice, address(erc677Receiver), amount, data);

        tfiToken.transferAndCall(address(erc677Receiver), amount, data);

        assertEq(tfiToken.balanceOf(address(erc677Receiver)), amount, "Received balance is invalid");
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
        vm.expectEmit(true, true, true, true, address(tfiToken));
        emit Transfer(alice, bob, amount, data);

        tfiToken.transferAndCall(bob, amount, data);

        assertEq(tfiToken.balanceOf(address(bob)), amount, "Received balance is invalid");
        vm.stopPrank();
    }
}
