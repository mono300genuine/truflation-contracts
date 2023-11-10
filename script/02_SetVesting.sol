// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../src/token/TruflationToken.sol";
import "../src/token/TfiVesting.sol";

contract Deploy is Script {
    using stdJson for string;

    TruflationToken public tfiToken = TruflationToken(address(0xe084FF9c00EcB4F86bBE5e495aED6A4aF0E0ea01));
    TfiVesting public vesting = TfiVesting(address(0x01B46B162436b95882e2B8AFA7f8bE21526207b2));

    address public tester = address(0x35e34513bdDA6Abe84b0081e7afD2cA0f6A784f5);
    address public tester1 = address(0xA954e5b2799dEDB5f947204eB0eF51449dB36D42);
    address public tester2 = address(0x755d9f370768a27DaCC99eaF2b38160B18cEFCF4);
    address public tester3 = address(0xa054C1Ae7AF88E69d9E0a036a9A3AF52D4f64352);
    address public tester4 = address(0x8B92c5D7bf3a4133FCedB1b641Cbd61dAE939d08);
    address public tester5 = address(0x4638a540107930B50eEc3AF600c23112ff86AFB0);
    address public tester6 = address(0xFED3573eBD238fDDdEe4FC1aAf659a5693d11721);
    address public tester8 = address(0x92c1e9E7C6452F7CF3Bac2cD2a613A252C337506);
    address public tester9 = address(0xC5F1D899DE43Ba60e3e3fEE905DC297A3abA4435);
    address public tester10 = address(0xD28b288B5D4a6Fdef4ac1fF751d827C21C27bBA8);
    address public tester11 = address(0xD361117eB62b0A04d72f5a5E09FcCeEaE492E664);

    function setUp() public {}

    struct CategoryParam {
        string name;
        uint256 allocation;
    }

    struct UserParams {
        uint256 categoryId;
        uint256 vestingId;
        address user;
        uint256 amount;
    }

    CategoryParam[] public categoryParams;

    TfiVesting.VestingInfo[] public vestingParams;

    UserParams[] public userParams;

    function run() public {
        categoryParams.push(CategoryParam("Preseed Round", 3_428_000));
        categoryParams.push(CategoryParam("Seed Round", 7_820_000));
        categoryParams.push(CategoryParam("Private", 6_860_000));
        categoryParams.push(CategoryParam("Team & Recruitment", 13_000_000));
        categoryParams.push(CategoryParam("Advisors", 5_000_000));
        categoryParams.push(CategoryParam("Ecosystem Community", 16_000_000));
        categoryParams.push(CategoryParam("Product Development", 10_000_000));
        categoryParams.push(CategoryParam("Liquidity", 12_892_000));
        categoryParams.push(CategoryParam("Staking Rewards", 25_000_000));

        vestingParams.push(TfiVesting.VestingInfo(500, 0, 0, 5 days, 1 hours));
        vestingParams.push(TfiVesting.VestingInfo(500, 0, 0, 5 days, 1 hours));
        vestingParams.push(TfiVesting.VestingInfo(500, 0, 0, 5 days, 1 hours));
        vestingParams.push(TfiVesting.VestingInfo(0, 0, 2 days, 10 days, 1 hours));
        vestingParams.push(TfiVesting.VestingInfo(0, 0, 2 days, 10 days, 1 hours));
        vestingParams.push(TfiVesting.VestingInfo(1000, 0, 0, 10 days, 6 hours));
        vestingParams.push(TfiVesting.VestingInfo(500, 0, 2 days, 5 days, 1 hours));
        vestingParams.push(TfiVesting.VestingInfo(2000, 0, 0, 12 days, 1 minutes));
        vestingParams.push(TfiVesting.VestingInfo(0, 0, 1 hours, 12 days, 1 hours));

        userParams.push(UserParams(0, 0, tester, 1000));
        userParams.push(UserParams(1, 0, tester, 2000));
        userParams.push(UserParams(2, 0, tester1, 1500));
        userParams.push(UserParams(3, 0, tester, 100));
        userParams.push(UserParams(4, 0, tester3, 500));
        userParams.push(UserParams(5, 0, tester2, 1100));
        userParams.push(UserParams(6, 0, tester, 1800));
        userParams.push(UserParams(7, 0, tester, 3000));
        userParams.push(UserParams(3, 0, tester6, 2500));
        userParams.push(UserParams(2, 0, tester2, 110));
        userParams.push(UserParams(7, 0, tester3, 2800));
        userParams.push(UserParams(2, 0, tester5, 1500));

        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);

        vesting.setTgeTime(1698327000);

        tfiToken.approve(address(vesting), type(uint256).max);

        for (uint256 i; i < categoryParams.length; i += 1) {
            vesting.setVestingCategory(type(uint256).max, categoryParams[i].name, categoryParams[i].allocation * 1e18);
            vesting.setVestingInfo(i, type(uint256).max, vestingParams[i]);
        }

        for (uint256 i; i < userParams.length; i += 1) {
            vesting.setUserVesting(
                userParams[i].categoryId, userParams[i].vestingId, userParams[i].user, 0, userParams[i].amount * 1e18
            );
        }

        vm.stopBroadcast();
    }
}
