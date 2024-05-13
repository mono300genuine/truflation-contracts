// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title TrufMigrator smart contract
 * @author Truflation Team
 * @notice Users can claim tokens based on a snapshot we create, the backend will give them "approval" to claim using an ECDSA signature.
 */
contract TrufMigrator is Ownable2Step {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    /********************** Errors ***********************/

    error InvalidSignature();
    error AlreadyMigrated();

    /********************** Events ***********************/

    event Migrated(address indexed user, uint256 amount);

    /********************** Constants ***********************/

    address public immutable SIGNER;
    IERC20 public immutable TRUF_TOKEN;

    /********************** Storage ***********************/

    mapping(address => uint256) public migratedAmount;

    /********************** Constructor ***********************/

    constructor(address _trufToken, address _signer) {
        TRUF_TOKEN = IERC20(_trufToken);
        SIGNER = _signer;
    }

    /********************** Core Functions ***********************/

    /**
     * Claim new TRUF token based on snapshot
     * @param maxMigrationAmount the maximum allowed migration amount
     * @param v the v parameter of the signature
     * @param r the r parameter of the signature
     * @param s the s parameter of the signature
     */
    function migrate(uint256 maxMigrationAmount, uint8 v, bytes32 r, bytes32 s) external {
        if(verify(msg.sender, maxMigrationAmount, v, r, s) == false) revert InvalidSignature();

        uint256 _migratedAmount = migratedAmount[msg.sender];

        if (maxMigrationAmount <= _migratedAmount) {
            revert AlreadyMigrated();
        }

        migratedAmount[msg.sender] = maxMigrationAmount;

        uint256 migrationAmount = maxMigrationAmount - _migratedAmount;
        TRUF_TOKEN.safeTransfer(msg.sender, migrationAmount);

        emit Migrated(msg.sender, migrationAmount);
    }

    /********************** Owner Only Functions ***********************/

    /**
     * Withdraw TRUF tokens
     * @notice Only owner can call
     * @param amount withdrawal amount
     */
    function withdrawTruf(uint256 amount) external onlyOwner {
        TRUF_TOKEN.safeTransfer(msg.sender, amount);
    }

    /********************** Internal Functions ***********************/

    function verify(address user, uint256 maxMigrationAmount, uint8 v, bytes32 r, bytes32 s) public view returns(bool) {
        return keccak256(abi.encodePacked(user, maxMigrationAmount)).toEthSignedMessageHash().recover(v, r, s) == SIGNER;
    }
}
