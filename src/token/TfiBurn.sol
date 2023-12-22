// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title TfiBurn smart contract
 * @author Ryuhei Matsuda
 * @notice Allow users to burn old TFI tokens
 */
contract TfiBurn {
    using SafeERC20 for IERC20;

    event BurnedOldTfi(address indexed user, uint256 amount);

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    IERC20 public immutable oldTfi;

    constructor(address _oldTfi) {
        oldTfi = IERC20(_oldTfi);
    }

    function burnOldTfi(uint256 amount) public {
        if (amount == 0) {
            revert Errors.ZeroAmount();
        }

        oldTfi.safeTransferFrom(msg.sender, BURN_ADDRESS, amount);

        emit BurnedOldTfi(msg.sender, amount);
    }
}
