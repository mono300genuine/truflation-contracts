// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../src/token/TruflationToken.sol";
import "../src/token/TrufVesting.sol";

contract Deploy is Script {
    using stdJson for string;

    TruflationToken public tfiToken = TruflationToken(address(0x9e44caa00C1629a05fFd9FAFe156CF842cfD9828));
    TrufVesting public vesting = TrufVesting(address(0x2B81F12D1f0a7bC5Ff352deC9Ed635Eb75462878));

    address public tester = address(0x35e34513bdDA6Abe84b0081e7afD2cA0f6A784f5);
    address public tester1 = address(0xA954e5b2799dEDB5f947204eB0eF51449dB36D42);
    address public tester2 = address(0x755d9f370768a27DaCC99eaF2b38160B18cEFCF4);
    address public tester3 = address(0xa054C1Ae7AF88E69d9E0a036a9A3AF52D4f64352);
    address public tester4 = address(0x8B92c5D7bf3a4133FCedB1b641Cbd61dAE939d08);
    address public tester5 = address(0x4638a540107930B50eEc3AF600c23112ff86AFB0);
    address public tester6 = address(0xFED3573eBD238fDDdEe4FC1aAf659a5693d11721);
    address public tester8 = address(0x750E5C4dfEcF6Cd0cc536BAD3A1e336d6d847308);
    address public tester9 = address(0xC5F1D899DE43Ba60e3e3fEE905DC297A3abA4435);
    address public tester10 = address(0x8f6E5209741304dAaDc369c1562DE348C0022252);
    address public tester11 = address(0x8607523334BE6D29913b23D3fC3Bbafead57e176);
    address public tester12 = address(0xFcb1a059e6F62d29F2cE3988B3a6375e962b8267);

    function setUp() public {}

    struct CategoryParam {
        string name;
        uint256 allocation;
        bool adminClaimable;
    }

    struct UserParams {
        uint256 categoryId;
        uint256 vestingId;
        address user;
        uint256 amount;
    }

    CategoryParam[] public categoryParams;

    TrufVesting.VestingInfo[] public vestingParams;

    UserParams[] public userParams;

    function run() public {
        categoryParams.push(CategoryParam("Preseed Round", 3_428_000, false));
        categoryParams.push(CategoryParam("Seed Round", 7_820_000, false));
        categoryParams.push(CategoryParam("Private", 6_860_000, false));
        categoryParams.push(CategoryParam("Team & Recruitment", 13_000_000, false));
        categoryParams.push(CategoryParam("Advisors", 5_000_000, false));
        categoryParams.push(CategoryParam("Ecosystem Community", 16_000_000, true));
        categoryParams.push(CategoryParam("Product Development", 10_000_000, true));
        categoryParams.push(CategoryParam("Liquidity", 12_892_000, true));
        categoryParams.push(CategoryParam("Staking Rewards", 24_000_000, true));

        vestingParams.push(TrufVesting.VestingInfo(500, 0, 0, 5 days, 1 hours));
        vestingParams.push(TrufVesting.VestingInfo(500, 0, 0, 5 days, 1 hours));
        vestingParams.push(TrufVesting.VestingInfo(500, 0, 0, 5 days, 1 hours));
        vestingParams.push(TrufVesting.VestingInfo(0, 0, 2 days, 10 days, 1 hours));
        vestingParams.push(TrufVesting.VestingInfo(0, 0, 2 days, 10 days, 1 hours));
        vestingParams.push(TrufVesting.VestingInfo(1000, 0, 0, 10 days, 6 hours));
        vestingParams.push(TrufVesting.VestingInfo(500, 0, 2 days, 5 days, 1 hours));
        vestingParams.push(TrufVesting.VestingInfo(2000, 0, 0, 12 days, 1 minutes));
        vestingParams.push(TrufVesting.VestingInfo(0, 0, 1 hours, 12 days, 1 hours));

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
        userParams.push(UserParams(2, 0, tester8, 3800));
        userParams.push(UserParams(1, 0, tester10, 2500));
        userParams.push(UserParams(2, 0, tester11, 3000));
        userParams.push(UserParams(0, 0, tester11, 3000));
        userParams.push(UserParams(1, 0, tester12, 3000));

        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);

        tfiToken.approve(address(vesting), type(uint256).max);

        for (uint256 i; i < categoryParams.length; i += 1) {
            vesting.setVestingCategory(
                type(uint256).max,
                categoryParams[i].name,
                categoryParams[i].allocation * 1e18,
                categoryParams[i].adminClaimable
            );
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
