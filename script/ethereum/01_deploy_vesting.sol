// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../../src/token/TrufVesting.sol";
import "../../src/token/VotingEscrowTruf.sol";
import "../../src/staking/VirtualStakingRewards.sol";
import "../../src/interfaces/IERC677.sol";

contract DeployVesting is Script {
    using stdJson for string;

    IERC677 public tfiToken;
    TrufVesting public vesting;
    VotingEscrowTruf public veTRUF;
    VirtualStakingRewards public tfiStakingRewards;
    uint256[] emissions;
    uint256[] privateInvestors;
    uint256[] productDevelopment;
    uint256[] ecosystem;
    uint256[] team;
    uint256[] advisors;
    uint256[] networkRewards;
    uint256[] liquidity;
    uint256[] strategicInvestors;

    uint64 constant MONTH = 30 days;

    uint256 privateInvestorsMaxAllocation;
    uint256 productMaxAllocation;
    uint256 ecosystemMaxAllocation;
    uint256 teamMaxAllocation;
    uint256 advisorsMaxAllocation;
    uint256 networkRewardsMaxAllocation;
    uint256 liquidityMaxAllocation;
    uint256 strategicInvestorsMaxAllocation;

    function setUp() public {}

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address adminAddress = vm.envAddress("ADMIN_ADDRESS");
        address trufToken = vm.envAddress("TRUF_TOKEN");

        vm.startBroadcast(privateKey);

        tfiToken = IERC677(trufToken);
        tfiToken.approve(address(vesting), type(uint256).max);

        uint64 tgeTime = 1712676600;
        vesting = new TrufVesting(tfiToken, tgeTime);
        tfiStakingRewards = new VirtualStakingRewards(vm.addr(privateKey), address(tfiToken));
        veTRUF = new VotingEscrowTruf(address(tfiToken), address(vesting), 1 hours, address(tfiStakingRewards));
        tfiStakingRewards.setOperator(address(veTRUF));
        vesting.setVeTruf(address(veTRUF));

        tfiStakingRewards.setRewardsDuration(30 days);

        privateInvestorsMaxAllocation = 214_741_557_130e15;
        vesting.setVestingCategory(type(uint256).max, "Private Investors", privateInvestorsMaxAllocation, false);
        productMaxAllocation = 100_000_000e18;
        vesting.setVestingCategory(type(uint256).max, "Product Development", productMaxAllocation, false);
        ecosystemMaxAllocation = 165_000_000e18;
        vesting.setVestingCategory(type(uint256).max, "Ecosystem / Community", ecosystemMaxAllocation, false);
        teamMaxAllocation = 130_000_000e18;
        vesting.setVestingCategory(type(uint256).max, "Team", teamMaxAllocation, false);
        advisorsMaxAllocation = 20_000_000e18;
        vesting.setVestingCategory(type(uint256).max, "Advisors", advisorsMaxAllocation, false);
        networkRewardsMaxAllocation = 200_000_000e18;
        vesting.setVestingCategory(type(uint256).max, "Network Rewards", networkRewardsMaxAllocation, false);
        liquidityMaxAllocation = 120_000_000e18;
        vesting.setVestingCategory(type(uint256).max, "Liquidity", liquidityMaxAllocation, false);
        strategicInvestorsMaxAllocation = 15_000_000e18;
        vesting.setVestingCategory(type(uint256).max, "Strategic Investors", strategicInvestorsMaxAllocation, false);

        // create emissions
        getPrivateInvestorsEmission();
        getProductDevelopmentEmission();
        getEcosystemEmissions();
        getTeamEmission();
        getAdvisorsEmission();
        getNetworkRewardsEmission();
        getLiquidityEmission();
        getStrategicInvestorsEmission();

        vesting.setEmissionSchedule(0, privateInvestors);
        vesting.setEmissionSchedule(1, productDevelopment);
        vesting.setEmissionSchedule(2, ecosystem);
        vesting.setEmissionSchedule(3, team);
        vesting.setEmissionSchedule(4, advisors);
        vesting.setEmissionSchedule(5, networkRewards);
        vesting.setEmissionSchedule(6, liquidity);
        vesting.setEmissionSchedule(7, strategicInvestors);

        vesting.setAdmin(adminAddress, true);

        TrufVesting.VestingInfo memory privateInvestorsVesting = TrufVesting.VestingInfo(
            0,
            0,
            0,
            24 * MONTH, // 24 months
            3600
        );

        TrufVesting.VestingInfo memory productVesting = TrufVesting.VestingInfo(
            500,
            0,
            10 * MONTH, // 10 months
            96 * MONTH, // 96 months
            3600
        );

        TrufVesting.VestingInfo memory ecosystemVesting = TrufVesting.VestingInfo(
            1000,
            0,
            0,
            96 * MONTH, // 96 months
            3600
        );

        TrufVesting.VestingInfo memory teamVesting = TrufVesting.VestingInfo(
            0,
            0,
            5 * MONTH,
            53 * MONTH, // 53 months
            3600
        );

        TrufVesting.VestingInfo memory advisorsVesting = TrufVesting.VestingInfo(
            0,
            0,
            10 * MONTH,
            58 * MONTH, // 58 months
            3600
        );

        TrufVesting.VestingInfo memory networkRewardsVesting = TrufVesting.VestingInfo(
            0,
            0,
            0,
            96 * MONTH, // 96 months
            3600
        );

        TrufVesting.VestingInfo memory liquidityVesting = TrufVesting.VestingInfo(
            5000,
            0,
            0,
            96 * MONTH, // 96 months
            3600
        );

        TrufVesting.VestingInfo memory strategicPartnersVesting = TrufVesting.VestingInfo(
            0,
            0,
            0,
            10 * MONTH, // 10 months
            3600
        );

        vesting.setVestingInfo(0, type(uint256).max, privateInvestorsVesting);
        vesting.setVestingInfo(1, type(uint256).max, productVesting);
        vesting.setVestingInfo(2, type(uint256).max, ecosystemVesting);
        vesting.setVestingInfo(3, type(uint256).max, teamVesting);
        vesting.setVestingInfo(4, type(uint256).max, advisorsVesting);
        vesting.setVestingInfo(5, type(uint256).max, networkRewardsVesting);
        vesting.setVestingInfo(6, type(uint256).max, liquidityVesting);
        vesting.setVestingInfo(7, type(uint256).max, strategicPartnersVesting);
        vm.stopBroadcast();
    }

    function getPrivateInvestorsEmission() internal {
        privateInvestors = [
            privateInvestorsMaxAllocation / 23,
            privateInvestorsMaxAllocation / 23 * 2,
            privateInvestorsMaxAllocation / 23 * 3,
            privateInvestorsMaxAllocation / 23 * 4,
            privateInvestorsMaxAllocation / 23 * 5,
            privateInvestorsMaxAllocation / 23 * 6,
            privateInvestorsMaxAllocation / 23 * 7,
            privateInvestorsMaxAllocation / 23 * 8,
            privateInvestorsMaxAllocation / 23 * 9,
            privateInvestorsMaxAllocation / 23 * 10,
            privateInvestorsMaxAllocation / 23 * 11,
            privateInvestorsMaxAllocation / 23 * 12,
            privateInvestorsMaxAllocation / 23 * 13,
            privateInvestorsMaxAllocation / 23 * 14,
            privateInvestorsMaxAllocation / 23 * 15,
            privateInvestorsMaxAllocation / 23 * 16,
            privateInvestorsMaxAllocation / 23 * 17,
            privateInvestorsMaxAllocation / 23 * 18,
            privateInvestorsMaxAllocation / 23 * 19,
            privateInvestorsMaxAllocation / 23 * 20,
            privateInvestorsMaxAllocation / 23 * 21,
            privateInvestorsMaxAllocation / 23 * 22,
            privateInvestorsMaxAllocation
        ];
    }

    function getProductDevelopmentEmission() internal {
        productDevelopment = [
            5000000e18,
            5000000e18,
            5000000e18,
            5000000e18,
            5000000e18,
            5000000e18,
            5000000e18,
            5000000e18,
            5000000e18,
            5000000e18,
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 2),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 3),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 4),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 5),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 6),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 7),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 8),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 9),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 10),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 11),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 12),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 13),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 14),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 15),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 16),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 17),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 18),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 19),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 20),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 21),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 22),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 23),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 24),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 25),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 26),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 27),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 28),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 29),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 30),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 31),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 32),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 33),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 34),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 35),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 36),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 37),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 38),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 39),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 40),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 41),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 42),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 43),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 44),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 45),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 46),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 47),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 48),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 49),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 50),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 51),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 52),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 53),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 54),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 55),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 56),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 57),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 58),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 59),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 60),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 61),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 62),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 63),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 64),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 65),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 66),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 67),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 68),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 69),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 70),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 71),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 72),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 73),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 74),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 75),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 76),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 77),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 78),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 79),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 80),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 81),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 82),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 83),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 84),
            5000000e18 + ((productMaxAllocation - 5000000e18) / 86 * 85),
            productMaxAllocation
        ];
    }

    function getEcosystemEmissions() internal {
        ecosystem = [
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 2),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 3),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 4),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 5),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 6),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 7),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 8),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 9),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 10),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 11),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 12),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 13),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 14),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 15),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 16),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 17),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 18),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 19),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 20),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 21),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 22),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 23),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 24),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 25),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 26),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 27),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 28),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 29),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 30),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 31),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 32),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 33),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 34),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 35),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 36),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 37),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 38),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 39),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 40),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 41),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 42),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 43),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 44),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 45),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 46),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 47),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 48),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 49),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 50),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 51),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 52),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 53),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 54),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 55),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 56),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 57),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 58),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 59),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 60),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 61),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 62),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 63),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 64),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 65),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 66),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 67),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 68),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 69),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 70),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 71),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 72),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 73),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 74),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 75),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 76),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 77),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 78),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 79),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 80),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 81),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 82),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 83),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 84),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 85),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 86),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 87),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 88),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 89),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 90),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 91),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 92),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 93),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 94),
            16500000e18 + ((ecosystemMaxAllocation - 16500000e18) / 96 * 95),
            ecosystemMaxAllocation
        ];
    }

    function getTeamEmission() internal {
        team = [
            0,
            0,
            0,
            0,
            0,
            teamMaxAllocation / 48,
            teamMaxAllocation / 48 * 2,
            teamMaxAllocation / 48 * 3,
            teamMaxAllocation / 48 * 4,
            teamMaxAllocation / 48 * 5,
            teamMaxAllocation / 48 * 6,
            teamMaxAllocation / 48 * 7,
            teamMaxAllocation / 48 * 8,
            teamMaxAllocation / 48 * 9,
            teamMaxAllocation / 48 * 10,
            teamMaxAllocation / 48 * 11,
            teamMaxAllocation / 48 * 12,
            teamMaxAllocation / 48 * 13,
            teamMaxAllocation / 48 * 14,
            teamMaxAllocation / 48 * 15,
            teamMaxAllocation / 48 * 16,
            teamMaxAllocation / 48 * 17,
            teamMaxAllocation / 48 * 18,
            teamMaxAllocation / 48 * 19,
            teamMaxAllocation / 48 * 20,
            teamMaxAllocation / 48 * 21,
            teamMaxAllocation / 48 * 22,
            teamMaxAllocation / 48 * 23,
            teamMaxAllocation / 48 * 24,
            teamMaxAllocation / 48 * 25,
            teamMaxAllocation / 48 * 26,
            teamMaxAllocation / 48 * 27,
            teamMaxAllocation / 48 * 28,
            teamMaxAllocation / 48 * 29,
            teamMaxAllocation / 48 * 30,
            teamMaxAllocation / 48 * 31,
            teamMaxAllocation / 48 * 32,
            teamMaxAllocation / 48 * 33,
            teamMaxAllocation / 48 * 34,
            teamMaxAllocation / 48 * 35,
            teamMaxAllocation / 48 * 36,
            teamMaxAllocation / 48 * 37,
            teamMaxAllocation / 48 * 38,
            teamMaxAllocation / 48 * 39,
            teamMaxAllocation / 48 * 40,
            teamMaxAllocation / 48 * 41,
            teamMaxAllocation / 48 * 42,
            teamMaxAllocation / 48 * 43,
            teamMaxAllocation / 48 * 44,
            teamMaxAllocation / 48 * 45,
            teamMaxAllocation / 48 * 46,
            teamMaxAllocation / 48 * 47,
            teamMaxAllocation
        ];
    }

    function getAdvisorsEmission() internal {
        advisors = [
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            advisorsMaxAllocation / 48,
            advisorsMaxAllocation / 48 * 2,
            advisorsMaxAllocation / 48 * 3,
            advisorsMaxAllocation / 48 * 4,
            advisorsMaxAllocation / 48 * 5,
            advisorsMaxAllocation / 48 * 6,
            advisorsMaxAllocation / 48 * 7,
            advisorsMaxAllocation / 48 * 8,
            advisorsMaxAllocation / 48 * 9,
            advisorsMaxAllocation / 48 * 10,
            advisorsMaxAllocation / 48 * 11,
            advisorsMaxAllocation / 48 * 12,
            advisorsMaxAllocation / 48 * 13,
            advisorsMaxAllocation / 48 * 14,
            advisorsMaxAllocation / 48 * 15,
            advisorsMaxAllocation / 48 * 16,
            advisorsMaxAllocation / 48 * 17,
            advisorsMaxAllocation / 48 * 18,
            advisorsMaxAllocation / 48 * 19,
            advisorsMaxAllocation / 48 * 20,
            advisorsMaxAllocation / 48 * 21,
            advisorsMaxAllocation / 48 * 22,
            advisorsMaxAllocation / 48 * 23,
            advisorsMaxAllocation / 48 * 24,
            advisorsMaxAllocation / 48 * 25,
            advisorsMaxAllocation / 48 * 26,
            advisorsMaxAllocation / 48 * 27,
            advisorsMaxAllocation / 48 * 28,
            advisorsMaxAllocation / 48 * 29,
            advisorsMaxAllocation / 48 * 30,
            advisorsMaxAllocation / 48 * 31,
            advisorsMaxAllocation / 48 * 32,
            advisorsMaxAllocation / 48 * 33,
            advisorsMaxAllocation / 48 * 34,
            advisorsMaxAllocation / 48 * 35,
            advisorsMaxAllocation / 48 * 36,
            advisorsMaxAllocation / 48 * 37,
            advisorsMaxAllocation / 48 * 38,
            advisorsMaxAllocation / 48 * 39,
            advisorsMaxAllocation / 48 * 40,
            advisorsMaxAllocation / 48 * 41,
            advisorsMaxAllocation / 48 * 42,
            advisorsMaxAllocation / 48 * 43,
            advisorsMaxAllocation / 48 * 44,
            advisorsMaxAllocation / 48 * 45,
            advisorsMaxAllocation / 48 * 46,
            advisorsMaxAllocation / 48 * 47,
            advisorsMaxAllocation
        ];
    }

    function getNetworkRewardsEmission() internal {
        networkRewards = [
            networkRewardsMaxAllocation / 96,
            networkRewardsMaxAllocation / 96 * 2,
            networkRewardsMaxAllocation / 96 * 3,
            networkRewardsMaxAllocation / 96 * 4,
            networkRewardsMaxAllocation / 96 * 5,
            networkRewardsMaxAllocation / 96 * 6,
            networkRewardsMaxAllocation / 96 * 7,
            networkRewardsMaxAllocation / 96 * 8,
            networkRewardsMaxAllocation / 96 * 9,
            networkRewardsMaxAllocation / 96 * 10,
            networkRewardsMaxAllocation / 96 * 11,
            networkRewardsMaxAllocation / 96 * 12,
            networkRewardsMaxAllocation / 96 * 13,
            networkRewardsMaxAllocation / 96 * 14,
            networkRewardsMaxAllocation / 96 * 15,
            networkRewardsMaxAllocation / 96 * 16,
            networkRewardsMaxAllocation / 96 * 17,
            networkRewardsMaxAllocation / 96 * 18,
            networkRewardsMaxAllocation / 96 * 19,
            networkRewardsMaxAllocation / 96 * 20,
            networkRewardsMaxAllocation / 96 * 21,
            networkRewardsMaxAllocation / 96 * 22,
            networkRewardsMaxAllocation / 96 * 23,
            networkRewardsMaxAllocation / 96 * 24,
            networkRewardsMaxAllocation / 96 * 25,
            networkRewardsMaxAllocation / 96 * 26,
            networkRewardsMaxAllocation / 96 * 27,
            networkRewardsMaxAllocation / 96 * 28,
            networkRewardsMaxAllocation / 96 * 29,
            networkRewardsMaxAllocation / 96 * 30,
            networkRewardsMaxAllocation / 96 * 31,
            networkRewardsMaxAllocation / 96 * 32,
            networkRewardsMaxAllocation / 96 * 33,
            networkRewardsMaxAllocation / 96 * 34,
            networkRewardsMaxAllocation / 96 * 35,
            networkRewardsMaxAllocation / 96 * 36,
            networkRewardsMaxAllocation / 96 * 37,
            networkRewardsMaxAllocation / 96 * 38,
            networkRewardsMaxAllocation / 96 * 39,
            networkRewardsMaxAllocation / 96 * 40,
            networkRewardsMaxAllocation / 96 * 41,
            networkRewardsMaxAllocation / 96 * 42,
            networkRewardsMaxAllocation / 96 * 43,
            networkRewardsMaxAllocation / 96 * 44,
            networkRewardsMaxAllocation / 96 * 45,
            networkRewardsMaxAllocation / 96 * 46,
            networkRewardsMaxAllocation / 96 * 47,
            networkRewardsMaxAllocation / 96 * 48,
            networkRewardsMaxAllocation / 96 * 49,
            networkRewardsMaxAllocation / 96 * 50,
            networkRewardsMaxAllocation / 96 * 51,
            networkRewardsMaxAllocation / 96 * 52,
            networkRewardsMaxAllocation / 96 * 53,
            networkRewardsMaxAllocation / 96 * 54,
            networkRewardsMaxAllocation / 96 * 55,
            networkRewardsMaxAllocation / 96 * 56,
            networkRewardsMaxAllocation / 96 * 57,
            networkRewardsMaxAllocation / 96 * 58,
            networkRewardsMaxAllocation / 96 * 59,
            networkRewardsMaxAllocation / 96 * 60,
            networkRewardsMaxAllocation / 96 * 61,
            networkRewardsMaxAllocation / 96 * 62,
            networkRewardsMaxAllocation / 96 * 63,
            networkRewardsMaxAllocation / 96 * 64,
            networkRewardsMaxAllocation / 96 * 65,
            networkRewardsMaxAllocation / 96 * 66,
            networkRewardsMaxAllocation / 96 * 67,
            networkRewardsMaxAllocation / 96 * 68,
            networkRewardsMaxAllocation / 96 * 69,
            networkRewardsMaxAllocation / 96 * 70,
            networkRewardsMaxAllocation / 96 * 71,
            networkRewardsMaxAllocation / 96 * 72,
            networkRewardsMaxAllocation / 96 * 73,
            networkRewardsMaxAllocation / 96 * 74,
            networkRewardsMaxAllocation / 96 * 75,
            networkRewardsMaxAllocation / 96 * 76,
            networkRewardsMaxAllocation / 96 * 77,
            networkRewardsMaxAllocation / 96 * 78,
            networkRewardsMaxAllocation / 96 * 79,
            networkRewardsMaxAllocation / 96 * 80,
            networkRewardsMaxAllocation / 96 * 81,
            networkRewardsMaxAllocation / 96 * 82,
            networkRewardsMaxAllocation / 96 * 83,
            networkRewardsMaxAllocation / 96 * 84,
            networkRewardsMaxAllocation / 96 * 85,
            networkRewardsMaxAllocation / 96 * 86,
            networkRewardsMaxAllocation / 96 * 87,
            networkRewardsMaxAllocation / 96 * 88,
            networkRewardsMaxAllocation / 96 * 89,
            networkRewardsMaxAllocation / 96 * 90,
            networkRewardsMaxAllocation / 96 * 91,
            networkRewardsMaxAllocation / 96 * 92,
            networkRewardsMaxAllocation / 96 * 93,
            networkRewardsMaxAllocation / 96 * 94,
            networkRewardsMaxAllocation / 96 * 95,
            networkRewardsMaxAllocation
        ];
    }

    function getLiquidityEmission() internal {
        liquidity = [
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 2),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 3),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 4),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 5),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 6),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 7),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 8),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 9),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 10),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 11),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 12),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 13),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 14),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 15),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 16),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 17),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 18),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 19),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 20),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 21),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 22),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 23),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 24),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 25),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 26),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 27),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 28),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 29),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 30),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 31),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 32),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 33),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 34),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 35),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 36),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 37),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 38),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 39),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 40),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 41),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 42),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 43),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 44),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 45),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 46),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 47),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 48),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 49),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 50),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 51),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 52),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 53),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 54),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 55),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 56),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 57),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 58),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 59),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 60),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 61),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 62),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 63),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 64),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 65),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 66),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 67),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 68),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 69),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 70),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 71),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 72),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 73),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 74),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 75),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 76),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 77),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 78),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 79),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 80),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 81),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 82),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 83),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 84),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 85),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 86),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 87),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 88),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 89),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 90),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 91),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 92),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 93),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 94),
            60000000e18 + ((liquidityMaxAllocation - 60000000e18) / 96 * 95),
            liquidityMaxAllocation
        ];
    }

    function getStrategicInvestorsEmission() internal {
        strategicInvestors = [
            strategicInvestorsMaxAllocation / 10,
            strategicInvestorsMaxAllocation / 10 * 2,
            strategicInvestorsMaxAllocation / 10 * 3,
            strategicInvestorsMaxAllocation / 10 * 4,
            strategicInvestorsMaxAllocation / 10 * 5,
            strategicInvestorsMaxAllocation / 10 * 6,
            strategicInvestorsMaxAllocation / 10 * 7,
            strategicInvestorsMaxAllocation / 10 * 8,
            strategicInvestorsMaxAllocation / 10 * 9,
            strategicInvestorsMaxAllocation
        ];
    }
}
