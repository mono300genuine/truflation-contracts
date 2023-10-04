// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./ERC677Token.sol";

contract TruflationToken is ERC677Token {
    constructor() ERC20("Truflation", "TFI") {
        _mint(msg.sender, 1e26);
    }
}
