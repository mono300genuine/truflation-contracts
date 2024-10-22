// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

interface IVirtualStakingRewards {
    // Views

    function balanceOf(address account) external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function getRewardForDuration() external view returns (uint256);

    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function rewardsDistribution() external view returns (address);

    function rewardsToken() external view returns (address);

    function totalSupply() external view returns (uint256);

    // Mutative

    function getReward(address user, address to) external returns (uint256);

    function stake(address user, uint256 amount) external;

    function withdraw(address user, uint256 amount) external;
}
