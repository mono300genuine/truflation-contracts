// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./ERC677Token.sol";

/**
 * @title TruflationToken smart contract
 * @author Ryuhei Matsuda
 * @notice ERC677 Token like LINK token
 *      name: Truflation
 *      symbol: TFI
 *      total supply: 100,000,000 TFI
 */
contract TruflationToken is ERC677Token {
    constructor() ERC20("Truflation", "TFI") {
        _mint(msg.sender, 100_000_000e18);
    }
}
