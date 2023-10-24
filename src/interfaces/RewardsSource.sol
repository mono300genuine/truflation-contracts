// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface RewardsSource {
    function previewRewards() external view returns (uint256);

    function collectRewards() external returns (uint256);
}
