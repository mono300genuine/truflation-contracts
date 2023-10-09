// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../src/token/TruflationToken.sol";
import "../src/token/TfiVesting.sol";

contract DeployTokenAndVesting is Script {
    using stdJson for string;

    TruflationToken public tfiToken;
    TfiVesting public vesting;

    function setUp() public {}

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);

        tfiToken = new TruflationToken();

        vesting = new TfiVesting(tfiToken);

        vm.stopBroadcast();
    }
}
