// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../../src/token/TruflationToken.sol";
import "../../src/token/TrufVesting.sol";
import "../../src/token/VotingEscrowTruf.sol";
import "../../src/staking/VirtualStakingRewards.sol";

contract TrufVestingCurveTest is Test {
    using stdJson for string;

    TruflationToken public tfiToken;
    TrufVesting public vesting;
    VotingEscrowTruf public veTRUF;
    VirtualStakingRewards public tfiStakingRewards;
    uint256[] emissions;
    uint256[] teamEmissions;
    uint256[] advisorEmissions;
    uint256[] ecosystemEmissions;
    uint256[] productEmissions;
    uint256[] liquidityEmissions;
    uint256[] stakingRewardsEmissions;
    uint256[] preseedRound;
    uint256[] seedRound;
    uint256[] privateRound;
    uint256[] private2Round;

    address public alice;
    address public bob;
    address public carol;
    address public owner;
    address public admin;
    uint64 tgeTime;

    function setUp() public {
        alice = address(uint160(uint256(keccak256(abi.encodePacked("Alice")))));
        bob = address(uint160(uint256(keccak256(abi.encodePacked("Bob")))));
        carol = address(uint160(uint256(keccak256(abi.encodePacked("Carol")))));
        owner = address(uint160(uint256(keccak256(abi.encodePacked("Owner")))));
        admin = address(uint160(uint256(keccak256(abi.encodePacked("Admin")))));

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(carol, "Carol");
        vm.label(owner, "Owner");
        vm.label(admin, "Admin");
        tgeTime = uint64(block.timestamp) + uint64(1);

        vm.startPrank(admin);
        tfiToken = new TruflationToken();
        vesting = new TrufVesting(tfiToken, tgeTime);
        tfiToken.approve(address(vesting), type(uint256).max);
        tfiStakingRewards = new VirtualStakingRewards(admin, address(tfiToken));
        veTRUF = new VotingEscrowTruf(address(tfiToken), address(vesting), 1 hours, address(tfiStakingRewards));
        tfiStakingRewards.setOperator(address(veTRUF));
        vesting.setVeTruf(address(veTRUF));

        tfiStakingRewards.setRewardsDuration(30 days);
        tfiToken.transfer(address(tfiStakingRewards), 100_000e18);
        tfiStakingRewards.notifyRewardAmount(100_000e18);
        
        vesting.setVestingCategory(type(uint256).max, "Team & Recruitment", 130000000e15, false);
        vesting.setVestingCategory(type(uint256).max, "Advisors", 40_000e18, false);
        vesting.setVestingCategory(type(uint256).max, "Ecosystem Community", 160_000e18, true);
        vesting.setVestingCategory(type(uint256).max, "Product Development", 100_000e18, true);
        vesting.setVestingCategory(type(uint256).max, "Liquidity", 120_000e18, true);
        vesting.setVestingCategory(type(uint256).max, "Staking Rewards", 200_000e18, true);
        vesting.setVestingCategory(type(uint256).max, "Preseed Round", 34_300e18, false);
        vesting.setVestingCategory(type(uint256).max, "Seed Round", 78_200e18, false);
        vesting.setVestingCategory(type(uint256).max, "Private", 107_500e18, false);
        vesting.setVestingCategory(type(uint256).max, "Private2", 30_000e18, false);

        // create emissions
        getTeamEmission();
        getAdvisorEmission();
        getEcosystemEmissions();
        getProductEmission();
        getLiquidityEmission();
        getStakingRewardsEmission();
        getPreseedRoundEmission();
        getSeedRoundEmission();
        getPrivateEmission();
        getPrivate2Emission();

        vesting.setEmissionSchedule(0, teamEmissions);
        vesting.setEmissionSchedule(1, advisorEmissions);
        vesting.setEmissionSchedule(2, ecosystemEmissions);
        vesting.setEmissionSchedule(3, productEmissions);
        vesting.setEmissionSchedule(4, liquidityEmissions);
        vesting.setEmissionSchedule(5, stakingRewardsEmissions);
        vesting.setEmissionSchedule(6, preseedRound);
        vesting.setEmissionSchedule(7, seedRound);
        vesting.setEmissionSchedule(8, privateRound);
        vesting.setEmissionSchedule(9, private2Round);

        vesting.setAdmin(admin, true);
        TrufVesting.VestingInfo memory vestInfo = TrufVesting.VestingInfo(
            0,
            0,
            0,
            30 days * 12 * 4,
            1 days
        );
        TrufVesting.VestingInfo memory vestInfo2 = TrufVesting.VestingInfo(
            1000,
            600,
            0,
            30 days * 12 * 4,
            1 days
        );
        vesting.setVestingInfo(0, type(uint256).max, vestInfo);
        vesting.setVestingInfo(1, type(uint256).max, vestInfo);
        vesting.setVestingInfo(2, type(uint256).max, vestInfo);
        vesting.setVestingInfo(0, type(uint256).max, vestInfo2);
        vesting.setVestingInfo(1, type(uint256).max, vestInfo2);
        vesting.setVestingInfo(2, type(uint256).max, vestInfo2);

        vesting.setUserVesting(0, 0, admin, 0, 100e18);
        vesting.setUserVesting(0, 1, admin, 0, 130_000e18 - 100e18);
        vesting.setUserVesting(1, 0, admin, 0, 50e18);
        vesting.setUserVesting(1, 1, admin, 0, 50e18);
        vesting.setUserVesting(2, 0, admin, 0, 50e18);
        vesting.setUserVesting(2, 1, admin, 0, 50e18);
    }

    function getTeamEmission() internal {
        teamEmissions = [
            0, 0, 0, 0, 0, 0, 0, 0, 0, 2407407e15, 4814815e15, 7222222e15, 9629630e15, 12037037e15, 
            14444444e15, 16851852e15, 19259259e15, 21666667e15, 24074074e15, 26481481e15, 28888889e15,
            31296296e15, 33703704e15, 36111111e15, 38518519e15, 40925926e15, 43333333e15, 45740741e15, 
            48148148e15, 50555556e15, 52962963e15, 55370370e15, 57777778e15, 60185185e15, 62592593e15, 
            65000000e15, 67407407e15, 69814815e15, 72222222e15, 74629630e15, 77037037e15, 79444444e15,
            81851852e15, 84259259e15, 86666667e15, 89074074e15, 91481481e15, 93888889e15, 96296296e15, 
            98703704e15, 101111111e15, 103518519e15, 105925926e15, 108333333e15, 110740741e15, 
            113148148e15, 115555556e15, 117962963e15, 120370370e15, 122777778e15, 125185185e15, 
            127592593e15, 130000000e15, 130000000e15, 130000000e15, 130000000e15, 130000000e15, 
            130000000e15, 130000000e15, 130000000e15, 130000000e15, 130000000e15, 130000000e15, 
            130000000e15, 130000000e15, 130000000e15, 130000000e15, 130000000e15, 130000000e15, 
            130000000e15, 130000000e15, 130000000e15, 130000000e15, 130000000e15, 130000000e15, 
            130000000e15, 130000000e15, 130000000e15, 130000000e15, 130000000e15, 130000000e15, 
            130000000e15, 130000000e15, 130000000e15, 130000000e15, 130000000e15, 130000000e15, 
            130000000e15, 130000000e15, 130000000e15, 130000000e15
        ];
    }

    function getAdvisorEmission() internal {
        advisorEmissions = [
            0, 0, 0, 0, 0, 0, 0, 0, 0, 833333e15, 1666667e15, 2500000e15, 3333333e15, 4166667e15, 
            5000000e15, 5833333e15, 6666667e15, 7500000e15, 8333333e15, 9166667e15, 10000000e15, 
            10833333e15, 11666667e15, 12500000e15, 13333333e15, 14166667e15, 15000000e15, 15833333e15, 
            16666667e15, 17500000e15, 18333333e15, 19166667e15, 20000000e15, 20833333e15, 21666667e15, 
            22500000e15, 23333333e15, 24166667e15, 25000000e15, 25833333e15, 26666667e15, 27500000e15, 
            28333333e15, 29166667e15, 30000000e15, 30833333e15, 31666667e15, 32500000e15, 33333333e15, 
            34166667e15, 35000000e15, 35833333e15, 36666667e15, 37500000e15, 38333333e15, 39166667e15, 
            40000000e15, 40000000e15, 40000000e15, 40000000e15, 40000000e15, 40000000e15, 40000000e15, 
            40000000e15, 40000000e15, 40000000e15, 40000000e15, 40000000e15, 40000000e15, 40000000e15, 
            40000000e15, 40000000e15, 40000000e15, 40000000e15, 40000000e15, 40000000e15, 40000000e15, 
            40000000e15, 40000000e15, 40000000e15, 40000000e15, 40000000e15, 40000000e15, 40000000e15, 
            40000000e15, 40000000e15, 40000000e15, 40000000e15, 40000000e15, 40000000e15, 40000000e15
        ];
    }

    function getEcosystemEmissions() internal {
        ecosystemEmissions = [0, 0, 0, 16000000e15, 17515789e15, 19031579e15, 20547368e15, 22063158e15, 23578947e15, 25094737e15, 26610526e15, 28126316e15, 29642105e15, 31157895e15, 32673684e15, 34189474e15, 35705263e15, 37221053e15, 38736842e15, 40252632e15, 41768421e15, 43284211e15, 44800000e15, 46315789e15, 47831579e15, 49347368e15, 50863158e15, 52378947e15, 53894737e15, 55410526e15, 56926316e15, 58442105e15, 59957895e15, 61473684e15, 62989474e15, 64505263e15, 66021053e15, 67536842e15, 69052632e15, 70568421e15, 72084211e15, 73600000e15, 75115789e15, 76631579e15, 78147368e15, 79663158e15, 81178947e15, 82694737e15, 84210526e15, 85726316e15, 87242105e15, 88757895e15, 90273684e15, 91789474e15, 93305263e15, 94821053e15, 96336842e15, 97852632e15, 99368421e15, 100884211e15, 102400000e15, 103915789e15, 105431579e15, 106947368e15, 108463158e15, 109978947e15, 111494737e15, 113010526e15, 114526316e15, 116042105e15, 117557895e15, 119073684e15, 120589474e15, 122105263e15, 123621053e15, 125136842e15, 126652632e15, 128168421e15, 129684211e15, 131200000e15, 132715789e15, 134231579e15, 135747368e15, 137263158e15, 138778947e15, 140294737e15, 141810526e15, 143326316e15, 144842105e15, 146357895e15, 147873684e15, 149389474e15, 150905263e15, 152421053e15, 153936842e15, 155452632e15, 156968421e15, 158484211e15, 160000000e15];
    }

    function getProductEmission() internal {
        productEmissions = [0, 0, 0, 5000000e15, 5000000e15, 5000000e15, 5000000e15, 5000000e15, 5000000e15, 5000000e15, 5000000e15, 5000000e15, 5000000e15, 5000000e15, 5000000e15, 6130952e15, 7261905e15, 8392857e15, 9523810e15, 10654762e15, 11785714e15, 12916667e15, 14047619e15, 15178571e15, 16309524e15, 17440476e15, 18571429e15, 19702381e15, 20833333e15, 21964286e15, 23095238e15, 24226190e15, 25357143e15, 26488095e15, 27619048e15, 28750000e15, 29880952e15, 31011905e15, 32142857e15, 33273810e15, 34404762e15, 35535714e15, 36666667e15, 37797619e15, 38928571e15, 40059524e15, 41190476e15, 42321429e15, 43452381e15, 44583333e15, 45714286e15, 46845238e15, 47976190e15, 49107143e15, 50238095e15, 51369048e15, 52500000e15, 53630952e15, 54761905e15, 55892857e15, 57023810e15, 58154762e15, 59285714e15, 60416667e15, 61547619e15, 62678571e15, 63809524e15, 64940476e15, 66071429e15, 67202381e15, 68333333e15, 69464286e15, 70595238e15, 71726190e15, 72857143e15, 73988095e15, 75119048e15, 76250000e15, 77380952e15, 78511905e15, 79642857e15, 80773810e15, 81904762e15, 83035714e15, 84166667e15, 85297619e15, 86428571e15, 87559524e15, 88690476e15, 89821429e15, 90952381e15, 92083333e15, 93214286e15, 94345238e15, 95476190e15, 96607143e15, 97738095e15, 98869048e15, 100000000e15];
    }

    function getLiquidityEmission() internal {
        liquidityEmissions = [0, 0, 0, 60000000e15, 60631579e15, 61263158e15, 61894737e15, 62526316e15, 63157895e15, 63789474e15, 64421053e15, 65052632e15, 65684211e15, 66315789e15, 66947368e15, 67578947e15, 68210526e15, 68842105e15, 69473684e15, 70105263e15, 70736842e15, 71368421e15, 72000000e15, 72631579e15, 73263158e15, 73894737e15, 74526316e15, 75157895e15, 75789474e15, 76421053e15, 77052632e15, 77684211e15, 78315789e15, 78947368e15, 79578947e15, 80210526e15, 80842105e15, 81473684e15, 82105263e15, 82736842e15, 83368421e15, 84000000e15, 84631579e15, 85263158e15, 85894737e15, 86526316e15, 87157895e15, 87789474e15, 88421053e15, 89052632e15, 89684211e15, 90315789e15, 90947368e15, 91578947e15, 92210526e15, 92842105e15, 93473684e15, 94105263e15, 94736842e15, 95368421e15, 96000000e15, 96631579e15, 97263158e15, 97894737e15, 98526316e15, 99157895e15, 99789474e15, 100421053e15, 101052632e15, 101684211e15, 102315789e15, 102947368e15, 103578947e15, 104210526e15, 104842105e15, 105473684e15, 106105263e15, 106736842e15, 107368421e15, 108000000e15, 108631579e15, 109263158e15, 109894737e15, 110526316e15, 111157895e15, 111789474e15, 112421053e15, 113052632e15, 113684211e15, 114315789e15, 114947368e15, 115578947e15, 116210526e15, 116842105e15, 117473684e15, 118105263e15, 118736842e15, 119368421e15, 120000000e15];
    }
    
    function getStakingRewardsEmission() internal {
        stakingRewardsEmissions = [0, 0, 0, 0, 2105263e15, 4210526e15, 6315789e15, 8421053e15, 10526316e15, 12631579e15, 14736842e15, 16842105e15, 18947368e15, 21052632e15, 23157895e15, 25263158e15, 27368421e15, 29473684e15, 31578947e15, 33684211e15, 35789474e15, 37894737e15, 40000000e15, 42105263e15, 44210526e15, 46315789e15, 48421053e15, 50526316e15, 52631579e15, 54736842e15, 56842105e15, 58947368e15, 61052632e15, 63157895e15, 65263158e15, 67368421e15, 69473684e15, 71578947e15, 73684211e15, 75789474e15, 77894737e15, 80000000e15, 82105263e15, 84210526e15, 86315789e15, 88421053e15, 90526316e15, 92631579e15, 94736842e15, 96842105e15, 98947368e15, 101052632e15, 103157895e15, 105263158e15, 107368421e15, 109473684e15, 111578947e15, 113684211e15, 115789474e15, 117894737e15, 120000000e15, 122105263e15, 124210526e15, 126315789e15, 128421053e15, 130526316e15, 132631579e15, 134736842e15, 136842105e15, 138947368e15, 141052632e15, 143157895e15, 145263158e15, 147368421e15, 149473684e15, 151578947e15, 153684211e15, 155789474e15, 157894737e15, 160000000e15, 162105263e15, 164210526e15, 166315789e15, 168421053e15, 170526316e15, 172631579e15, 174736842e15, 176842105e15, 178947368e15, 181052632e15, 183157895e15, 185263158e15, 187368421e15, 189473684e15, 191578947e15, 193684211e15, 195789474e15, 197894737e15, 200000000e15];
    }

    function getPreseedRoundEmission() internal {
        preseedRound = [0, 0, 0, 1715000e15, 3072708e15, 4430417e15, 5788125e15, 7145833e15, 8503542e15, 9861250e15, 11218958e15, 12576667e15, 13934375e15, 15292083e15, 16649792e15, 18007500e15, 19365208e15, 20722917e15, 22080625e15, 23438333e15, 24796042e15, 26153750e15, 27511458e15, 28869167e15, 30226875e15, 31584583e15, 32942292e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15, 34300000e15];
    }

    function getSeedRoundEmission() internal {
        seedRound = [0, 0, 0, 3910000e15, 7005417e15, 10100833e15, 13196250e15, 16291667e15, 19387083e15, 22482500e15, 25577917e15, 28673333e15, 31768750e15, 34864167e15, 37959583e15, 41055000e15, 44150417e15, 47245833e15, 50341250e15, 53436667e15, 56532083e15, 59627500e15, 62722917e15, 65818333e15, 68913750e15, 72009167e15, 75104583e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15, 78200000e15];
    }

    function getPrivateEmission() internal {
        privateRound = [0, 0, 0, 5375000e15, 9630208e15, 13885417e15, 18140625e15, 22395833e15, 26651042e15, 30906250e15, 35161458e15, 39416667e15, 43671875e15, 47927083e15, 52182292e15, 56437500e15, 60692708e15, 64947917e15, 69203125e15, 73458333e15, 77713542e15, 81968750e15, 86223958e15, 90479167e15, 94734375e15, 98989583e15, 103244792e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15, 107500000e15];
    }

    function getPrivate2Emission() internal {
        private2Round = [0, 0, 0, 1500000e15, 2687500e15, 3875000e15, 5062500e15, 6250000e15, 7437500e15, 8625000e15, 9812500e15, 11000000e15, 12187500e15, 13375000e15, 14562500e15, 15750000e15, 16937500e15, 18125000e15, 19312500e15, 20500000e15, 21687500e15, 22875000e15, 24062500e15, 25250000e15, 26437500e15, 27625000e15, 28812500e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15, 30000000e15];
    }

    function testMonthlyRelease() external {
        vm.startPrank(admin);
        vm.warp(tgeTime + 1 days * 30);
        uint256 claimable = vesting.claimable(0, 0, admin);
        assertEq(claimable, 0);

        vm.warp(tgeTime + 1 days * 30* 8);
        claimable = vesting.claimable(0, 0, admin);
        assertEq(claimable, 0);

        vm.warp(tgeTime + 1 days * 30 * 9);
        claimable = vesting.claimable(0, 0, admin);
        assertEq(claimable, 0);
        vm.warp(tgeTime + 30 days * 10);
        uint256 totalLength = 30 days * 12 * 4;
        // total user allocation / vesting period * duration
        uint256 expected = 100e18 * 30 days * 10 / totalLength;
        claimable = vesting.claimable(0, 0, admin);
        assertEq(claimable, expected);

        // test EoD amount
        vm.warp(tgeTime + 30 days * 12 * 4);
        claimable = vesting.claimable(0, 0, admin);
        assertEq(claimable, 100e18);
    }

    function testWhenEmissionReached() external {
        vm.startPrank(admin);
        vm.warp(tgeTime + 30 days * 10);
        uint256 totalLength = 30 days * 12 * 4;
        uint256 expected = (130_000e18 - 100e18) * 30 days * 10 / totalLength;
        if (expected > teamEmissions[9]) {
            expected = teamEmissions[9];
        }
        uint256 claimable = vesting.claimable(0, 1, admin);
        assertEq(claimable, expected);

        vm.warp(tgeTime + 30 days * 20);
        expected = (130_000e18 - 100e18) * 30 days * 20 / totalLength;
        if (expected > teamEmissions[19]) {
            expected = teamEmissions[19];
        }
        claimable = vesting.claimable(0, 1, admin);
        assertEq(claimable, expected);
    }

    function test2ndScenario() external {
        vm.startPrank(admin);
        vm.warp(tgeTime + 1 days * 30);
        uint256 claimable = vesting.claimable(1, 0, admin);
        assertEq(claimable, 0);

        vm.warp(tgeTime + 1 days * 30* 8);
        claimable = vesting.claimable(1, 0, admin);
        assertEq(claimable, 0);

        vm.warp(tgeTime + 1 days * 30 * 9);
        claimable = vesting.claimable(1, 0, admin);
        assertEq(claimable, 0);
        vm.warp(tgeTime + 30 days * 10);
        uint256 totalLength = 30 days * 12 * 4;
        // total user allocation / vesting period * duration
        uint256 expected = 50e18 * 30 days * 10 / totalLength;
        claimable = vesting.claimable(1, 0, admin);
        assertEq(claimable, expected);

        // test EoD amount
        vm.warp(tgeTime + 30 days * 12 * 4);
        claimable = vesting.claimable(0, 0, admin);
        assertEq(claimable, 100e18);
    }

    function testWithClaimed() external {
        vm.startPrank(admin);
        vm.warp(tgeTime + 1 days * 30);
        uint256 claimable = vesting.claimable(0, 0, admin);
        assertEq(claimable, 0);

        vm.warp(tgeTime + 1 days * 30 * 8);
        claimable = vesting.claimable(0, 0, admin);
        assertEq(claimable, 0);

        vm.warp(tgeTime + 1 days * 30 * 9);
        claimable = vesting.claimable(0, 0, admin);
        assertEq(claimable, 0);
        vm.warp(tgeTime + 30 days * 10);
        uint256 totalLength = 30 days * 12 * 4;
        // total user allocation / vesting period * duration
        uint256 expected = 100e18 * 30 days * 10 / totalLength;
        uint256 claimed = vesting.claimable(0, 0, admin);
        vesting.claim(admin, 0, 0, claimed);
        claimable = vesting.claimable(0, 0, admin);
        assertEq(claimable, 0);

        // test EoD amount
        vm.warp(tgeTime + 30 days * 12 * 4);
        claimable = vesting.claimable(0, 0, admin);
        assertEq(claimable, 100e18 - claimed);
    }
}