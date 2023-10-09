// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../interfaces/IERC677.sol";
import "../interfaces/IERC677Receiver.sol";

abstract contract ERC677Token is ERC20, IERC677 {
    /**
     * @dev transfer token to a contract address with additional data if the recipient is a contact.
     * @param _to The address to transfer to.
     * @param _value The amount to be transferred.
     * @param _data The extra data to be passed to the receiving contract.
     */
    function transferAndCall(address _to, uint256 _value, bytes calldata _data) public returns (bool success) {
        super.transfer(_to, _value);
        emit Transfer(msg.sender, _to, _value, _data);
        if (Address.isContract(_to)) {
            _contractFallback(_to, _value, _data);
        }
        return true;
    }

    // PRIVATE
    function _contractFallback(address _to, uint256 _value, bytes calldata _data) private {
        IERC677Receiver receiver = IERC677Receiver(_to);
        receiver.onTokenTransfer(msg.sender, _value, _data);
    }
}
