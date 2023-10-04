// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC677 is IERC20 {
    event Transfer(
        address indexed from,
        address indexed to,
        uint value,
        bytes data
    );

    function transferAndCall(
        address _to,
        uint _value,
        bytes calldata _data
    ) external returns (bool success);
}
