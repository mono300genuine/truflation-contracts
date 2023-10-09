// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "../../src/interfaces/IERC677Receiver.sol";

contract MockERC677Receiver is IERC677Receiver {
    address public sender;
    uint256 public value;
    bytes public data;

    function onTokenTransfer(address _sender, uint256 _value, bytes calldata _data) external override {
        sender = _sender;
        value = _value;
        data = _data;
    }
}
