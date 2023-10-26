// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../src/token/TruflationToken.sol";
import "../src/token/TfiVesting.sol";
import "../src/token/VotingEscrowTfi.sol";
import "../src/staking/VirtualStakingRewards.sol";

contract DeployTokenAndVesting is Script {
    using stdJson for string;

    TruflationToken public tfiToken;
    TfiVesting public vesting;
    VotingEscrowTfi public veTFI;
    VirtualStakingRewards public tfiStakingRewards;

    function setUp() public {}

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);

        tfiToken = new TruflationToken();

        vesting = new TfiVesting(tfiToken);

        tfiStakingRewards = new VirtualStakingRewards(vm.addr(privateKey), address(tfiToken));
        veTFI =
        new VotingEscrowTfi(address(tfiToken), address(vesting), block.timestamp, 1 hours, address(tfiStakingRewards));
        tfiStakingRewards.setOperator(address(veTFI));
        vesting.setVeTfi(address(veTFI));

        vm.stopBroadcast();
    }
}
