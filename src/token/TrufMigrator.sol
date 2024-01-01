// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title TrufMigrator smart contract
 * @author Ryuhei Matsuda
 * @notice Users could claim tokens based on snapshot(stored by merkle tree).
 */
contract TrufMigrator is Ownable2Step {
    using SafeERC20 for IERC20;

    error InvalidProof();
    error AlreadyMigrated();

    event SetMerkleRoot(bytes32 merkleRoot);
    event Migrated(address indexed user, uint256 amount);

    IERC20 public immutable trufToken;
    bytes32 public merkleRoot;
    mapping(address => uint256) public migratedAmount;

    constructor(address _trufToken) {
        trufToken = IERC20(_trufToken);
    }

    /**
     * Set merkle root
     * @notice Only owner can call
     * @param _merkleRoot Merkle root
     */
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;

        emit SetMerkleRoot(_merkleRoot);
    }

    /**
     * Claim new TRUF token based on snapshot(merkle tree)
     * @param index index of leaf
     * @param amount token amount
     * @param proof merkle proof
     */
    function migrate(uint256 index, uint256 amount, bytes32[] calldata proof) external {
        bytes32 leaf = keccak256(abi.encode(msg.sender, index, amount));

        if (MerkleProof.verify(proof, merkleRoot, leaf) == false) {
            revert InvalidProof();
        }

        uint256 _migratedAmount = migratedAmount[msg.sender];

        if (amount <= _migratedAmount) {
            revert AlreadyMigrated();
        }

        migratedAmount[msg.sender] = amount;

        uint256 migrateAmount = amount - _migratedAmount;
        trufToken.safeTransfer(msg.sender, migrateAmount);

        emit Migrated(msg.sender, migrateAmount);
    }

    /**
     * Withdraw TRUF tokens if we sent more tokens
     * @notice Only owner can call
     * @param amount Withdrawal amount
     */
    function withdrawTruf(uint256 amount) external onlyOwner {
        trufToken.safeTransfer(msg.sender, amount);
    }
}
