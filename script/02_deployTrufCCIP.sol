// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../src/token/TruflationTokenCCIP.sol";

contract DeployTokenCCIP is Script {
    using stdJson for string;

    TruflationTokenCCIP public tfiToken;

    function setUp() public {}

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);

        tfiToken = new TruflationTokenCCIP();

        vm.stopBroadcast();
    }
}
