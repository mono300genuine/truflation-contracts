// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {TruflationToken} from "../../src/token/TruflationToken.sol";
import {TrufMigrator} from "../../src/token/TrufMigrator.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract TrufMigratorTest is Test {
    using ECDSA for bytes32;

    TruflationToken public tfiToken;
    TrufMigrator public trufMigrator;

    uint256 constant MOCK_PK = uint256(keccak256("MOCK_PK"));
    address MOCK_PK_OWNER;

    function reset() internal {
        MOCK_PK_OWNER = vm.addr(MOCK_PK);
        tfiToken = new TruflationToken();
        trufMigrator = new TrufMigrator(address(tfiToken), MOCK_PK_OWNER);

        tfiToken.transfer(address(trufMigrator), tfiToken.balanceOf(address(this)));
    }

    function testValidMigration() external {
        reset();

        address user = address(bytes20(keccak256("user")));

        (uint8 v, bytes32 r, bytes32 s) = _getValidMigrationSignature(user, 10e18);

        vm.prank(user, user);
        trufMigrator.migrate(10e18, v, r, s);
        
        assertEq(tfiToken.balanceOf(user), 10e18, "Invalid TRUF balance after migration 1");

        (v, r, s) = _getValidMigrationSignature(user, 5e18);

        vm.startPrank(user, user);
        vm.expectRevert(TrufMigrator.AlreadyMigrated.selector);
        trufMigrator.migrate(5e18, v, r, s);
        vm.stopPrank();
        
        assertEq(tfiToken.balanceOf(user), 10e18, "Invalid TRUF balance after migration 2");

        (v, r, s) = _getValidMigrationSignature(user, 15e18);

        vm.prank(user, user);
        trufMigrator.migrate(15e18, v, r, s);
        
        assertEq(tfiToken.balanceOf(user), 15e18, "Invalid TRUF balance after migration 3");
    }

    function testInvalidUserMigration() external {
        reset();

        address user1 = address(bytes20(keccak256("user1")));
        address user2 = address(bytes20(keccak256("user2")));

        (uint8 v, bytes32 r, bytes32 s) = _getValidMigrationSignature(user1, 10e18);

        vm.startPrank(user2, user2);
        vm.expectRevert(TrufMigrator.InvalidSignature.selector);
        trufMigrator.migrate(10e18, v, r, s);
        vm.stopPrank();
    }

    function testInvalidAmountMigration() external {
        reset();

        address user = address(bytes20(keccak256("user")));

        (uint8 v, bytes32 r, bytes32 s) = _getValidMigrationSignature(user, 10e18);

        vm.startPrank(user, user);
        vm.expectRevert(TrufMigrator.InvalidSignature.selector);
        trufMigrator.migrate(100e18, v, r, s);
        vm.stopPrank();
    }

    function testOwnerOnly() external {
        reset();

        address user = address(bytes20(keccak256("user")));

        vm.startPrank(user, user);
        vm.expectRevert("Ownable: caller is not the owner");
        trufMigrator.withdrawTruf(1e18);
        vm.stopPrank();

        trufMigrator.withdrawTruf(1e18);
        assertEq(tfiToken.balanceOf(address(this)), 1e18, "withdrawTruf did not send the tokens");
    }

    function _getValidMigrationSignature(address user, uint256 amount) internal pure returns(uint8 v, bytes32 r, bytes32 s) {
        return vm.sign(MOCK_PK, keccak256(abi.encodePacked(user, amount)).toEthSignedMessageHash());
    }
}
