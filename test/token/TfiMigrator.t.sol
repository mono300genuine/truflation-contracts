// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "murky/src/Merkle.sol";
import "../../src/token/TruflationToken.sol";
import "../../src/token/TfiMigrator.sol";

contract TfiMigratorTest is Test, Merkle {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event SetMerkleRoot(bytes32 merkleRoot);
    event Migrated(address indexed user, uint256 amount);

    TruflationToken public tfiToken;
    TfiMigrator public tfiMigrator;

    // Users
    address public alice;
    address public owner;

    function setUp() public {
        alice = address(uint160(uint256(keccak256(abi.encodePacked("Alice")))));
        owner = address(uint160(uint256(keccak256(abi.encodePacked("Owner")))));

        vm.label(alice, "Alice");
        vm.label(owner, "Owner");

        vm.startPrank(owner);
        tfiToken = new TruflationToken();
        tfiMigrator = new TfiMigrator(address(tfiToken));

        tfiToken.transfer(address(tfiMigrator), 1e24);

        vm.stopPrank();
    }

    function testConstructorSuccess() external {
        console.log("Check initial variables");
        assertEq(address(tfiMigrator.tfiToken()), address(tfiToken), "Tfi token is invalid");
        assertEq(tfiMigrator.owner(), owner, "Owner is invalid");
    }

    function testSetMerkleRoot() external {
        bytes32 fakeMerkleRoot = keccak256("Fake Merkle Root");

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true, address(tfiMigrator));
        emit SetMerkleRoot(fakeMerkleRoot);

        tfiMigrator.setMerkleRoot(fakeMerkleRoot);

        vm.stopPrank();

        assertEq(tfiMigrator.merkleRoot(), fakeMerkleRoot, "Merkle root is invalid");
    }

    function testSetMerkleRootFailures() external {
        console.log("Revert if msg.sender is not owner");

        bytes32 fakeMerkleRoot = keccak256("Fake Merkle Root");

        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");

        tfiMigrator.setMerkleRoot(fakeMerkleRoot);

        vm.stopPrank();
    }

    function testMigrate() external {
        (address[] memory users, uint256[] memory amounts, bytes32[] memory leaves,) = _setupMerkleRoot();

        uint256 index = 3;
        address user = users[index];
        uint256 amount = amounts[index];

        vm.startPrank(user);
        vm.expectEmit(true, true, true, true, address(tfiMigrator));
        emit Migrated(user, amount);

        tfiMigrator.migrate(index, amount, getProof(leaves, index));

        vm.stopPrank();

        assertEq(tfiMigrator.migratedAmount(user), amount, "Migrated amount is invalid");
        assertEq(tfiToken.balanceOf(user), amount, "User did not receive TFI token");
    }

    function testMigrate_More() external {
        console.log("Allow users to migrate again if there are additional amounts added after new merkle root added");

        (address[] memory users, uint256[] memory amounts, bytes32[] memory leaves,) = _setupMerkleRoot();

        uint256 addedAmount = 15e19;

        uint256 index = 3;
        address user = users[index];
        uint256 amount = amounts[index];

        vm.startPrank(user);

        tfiMigrator.migrate(index, amount, getProof(leaves, index));

        vm.stopPrank();

        amounts[index] += addedAmount;

        (bytes32[] memory newLeaves, bytes32 merkleRoot) = _generateMerkleRoot(users, amounts);

        vm.startPrank(owner);

        tfiMigrator.setMerkleRoot(merkleRoot);

        vm.stopPrank();

        vm.startPrank(user);
        vm.expectEmit(true, true, true, true, address(tfiMigrator));
        emit Migrated(user, addedAmount);

        tfiMigrator.migrate(index, amounts[index], getProof(newLeaves, index));

        vm.stopPrank();

        assertEq(tfiMigrator.migratedAmount(user), amounts[index], "Migrated amount is invalid");
        assertEq(tfiToken.balanceOf(user), amounts[index], "User did not receive TFI token");
    }

    function testMigrateFailures() external {
        (address[] memory users, uint256[] memory amounts, bytes32[] memory leaves,) = _setupMerkleRoot();

        uint256 index = 3;
        address user = users[index];
        uint256 amount = amounts[index];

        vm.startPrank(user);

        console.log("Revert if proof is invalid");
        vm.expectRevert(abi.encodeWithSignature("InvalidProof()"));

        tfiMigrator.migrate(index, amount, getProof(leaves, index + 1));

        console.log("Revert if already migrated");
        tfiMigrator.migrate(index, amount, getProof(leaves, index));

        vm.expectRevert(abi.encodeWithSignature("AlreadyMigrated()"));

        tfiMigrator.migrate(index, amount, getProof(leaves, index));

        vm.stopPrank();
    }

    function testWithdrawTfi() external {
        uint256 amount = 1e18;

        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true, address(tfiToken));
        emit Transfer(address(tfiMigrator), owner, amount);
        tfiMigrator.withdrawTfi(amount);

        vm.stopPrank();
    }

    function testWithdrawTfiFailures() external {
        console.log("Revert if msg.sender is not owner");

        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");

        tfiMigrator.withdrawTfi(100);

        vm.stopPrank();
    }

    function _setupMerkleRoot()
        internal
        returns (address[] memory users, uint256[] memory amounts, bytes32[] memory leaves, bytes32 merkleRoot)
    {
        (users, amounts) = _getExampleSnapshot();
        (leaves, merkleRoot) = _generateMerkleRoot(users, amounts);

        vm.startPrank(owner);

        tfiMigrator.setMerkleRoot(merkleRoot);

        vm.stopPrank();
    }

    function _getExampleSnapshot() internal pure returns (address[] memory users, uint256[] memory amounts) {
        uint256 userLen = 10;
        users = new address[](userLen);
        amounts = new uint256[](userLen);

        for (uint256 i = 0; i < userLen; i += 1) {
            users[i] = address(uint160(uint256(keccak256(abi.encodePacked("User", i)))));
            amounts[i] = 1e18 * ((i + 3) % userLen + 1);
        }
    }

    function _generateMerkleRoot(address[] memory users, uint256[] memory amounts)
        internal
        pure
        returns (bytes32[] memory leaves, bytes32 merkleRoot)
    {
        leaves = new bytes32[](users.length);

        for (uint256 i = 0; i < users.length; i += 1) {
            leaves[i] = keccak256(abi.encode(users[i], i, amounts[i]));
        }

        merkleRoot = getRoot(leaves);
    }
}
