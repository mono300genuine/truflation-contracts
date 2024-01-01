// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "./ERC677Token.sol";

/**
 * @title CCIP wrapped TruflationToken
 * @author Ryuhei Matsuda
 * @notice The chainlink team is able to mint tokens for CCIP bridge
 */
contract TruflationTokenCCIP is ERC677Token, Ownable2Step {
    address public ccipPool;

    error Forbidden(address sender);
    error ZeroAddress();

    event CcipPoolSet(address indexed ccipPool);

    modifier onlyCcipPool() {
        if (msg.sender != ccipPool) {
            revert Forbidden(msg.sender);
        }

        _;
    }

    constructor() ERC20("Truflation", "TRUF") {
        // Do not mint any supply
    }

    /**
     * Mint TRUF token on other blockchains
     * @notice Only CCIP Token pool can mint tokens
     * @param account User address to get minted tokens
     * @param amount Token amount to mint
     */
    function mint(address account, uint256 amount) external onlyCcipPool {
        _mint(account, amount);
    }

    /**
     * Burn TRUF token of CCIP token pool for CCIP bridge
     * @notice Only CCIP Token pool can burn tokens
     * @param amount Token amount to burn
     */
    function burn(uint256 amount) external onlyCcipPool {
        _burn(msg.sender, amount);
    }

    /**
     * Set CCIP pool contract
     * @notice Only owner can set
     * @param _ccipPool New CCIP Pool address to be set
     */
    function setCcipPool(address _ccipPool) external onlyOwner {
        if (_ccipPool == address(0)) {
            revert ZeroAddress();
        }

        ccipPool = _ccipPool;

        emit CcipPoolSet(_ccipPool);
    }
}
