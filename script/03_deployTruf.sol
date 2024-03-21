// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../src/token/TruflationToken.sol";
import "../src/token/TrufVesting.sol";
import "../src/token/VotingEscrowTruf.sol";
import "../src/staking/VirtualStakingRewards.sol";

contract DeployToken is Script {
    using stdJson for string;

    function setUp() public {}
    TruflationToken public tfiToken;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);
        tfiToken = new TruflationToken();
    }
}
