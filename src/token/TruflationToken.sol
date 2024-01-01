// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./ERC677Token.sol";

/**
 * @title TruflationToken smart contract
 * @author Ryuhei Matsuda
 * @notice ERC677 Token like LINK token
 *      name: Truflation
 *      symbol: TRUF
 *      total supply: 100,000,000 TRUF
 */
contract TruflationToken is ERC677Token {
    constructor() ERC20("Truflation", "TRUF") {
        _mint(msg.sender, 1_000_000_000e18);
    }
}
