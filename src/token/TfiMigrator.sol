// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title TfiMigrator smart contract
 * @author Ryuhei Matsuda
 * @notice Users could claim tokens based on snapshot(stored by merkle tree).
 */
contract TfiMigrator is Ownable2Step {
    using SafeERC20 for IERC20;

    event SetMerkleRoot(bytes32 merkleRoot);
    event Migrated(address indexed user, uint256 amount);

    IERC20 public immutable tfiToken;
    bytes32 public merkleRoot;
    mapping(address => uint256) public migratedAmount;

    constructor(address _tfiToken) {
        tfiToken = IERC20(_tfiToken);
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;

        emit SetMerkleRoot(_merkleRoot);
    }

    function migrate(uint256 index, uint256 amount, bytes32[] calldata proof) external {
        bytes32 leaf = keccak256(abi.encode(msg.sender, index, amount));

        if (MerkleProof.verify(proof, merkleRoot, leaf) == false) {
            revert Errors.InvalidProof();
        }

        uint256 _migratedAmount = migratedAmount[msg.sender];

        if (amount <= _migratedAmount) {
            revert Errors.AlreadyMigrated();
        }

        migratedAmount[msg.sender] = amount;

        uint256 migrateAmount = amount - _migratedAmount;
        tfiToken.safeTransfer(msg.sender, migrateAmount);

        emit Migrated(msg.sender, migrateAmount);
    }

    function withdrawToken(uint256 amount) external onlyOwner {
        tfiToken.safeTransfer(msg.sender, amount);
    }
}
