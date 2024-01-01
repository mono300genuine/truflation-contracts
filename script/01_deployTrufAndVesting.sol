// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../src/token/TruflationToken.sol";
import "../src/token/TrufVesting.sol";
import "../src/token/VotingEscrowTruf.sol";
import "../src/staking/VirtualStakingRewards.sol";

contract DeployTokenAndVesting is Script {
    using stdJson for string;

    TruflationToken public tfiToken;
    TrufVesting public vesting;
    VotingEscrowTruf public veTRUF;
    VirtualStakingRewards public tfiStakingRewards;

    function setUp() public {}

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);

        tfiToken = new TruflationToken();

        uint64 tgeTime = 1702997500;
        vesting = new TrufVesting(tfiToken, tgeTime);

        tfiStakingRewards = new VirtualStakingRewards(vm.addr(privateKey), address(tfiToken));
        veTRUF = new VotingEscrowTruf(address(tfiToken), address(vesting), 1 hours, address(tfiStakingRewards));
        tfiStakingRewards.setOperator(address(veTRUF));
        vesting.setVeTruf(address(veTRUF));

        tfiStakingRewards.setRewardsDuration(30 days);
        tfiToken.transfer(address(tfiStakingRewards), 100_000e18);
        tfiStakingRewards.notifyRewardAmount(100_000e18);

        vm.stopBroadcast();
    }
}
