// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console2} from "forge-std/Test.sol";
import {StakeDropToken} from "../../src/StakeDropToken.sol";
import {StakeDropV1} from "../../src/StakeDrop.sol";
import {DeployStakeDrop} from "../../script/StakeDrop/DeployStakeDrop.s.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";

contract StakeDropTest is Test {
    DeployStakeDrop deployer;
    StakeDropToken token;
    StakeDropV1 stakeDrop;

    address USER = makeAddr("user");
    uint256 constant USER_BALANCE = 100 ether;
    uint256 constant VALUE = 1 ether;
    uint256 initialBalance = 100 ether;
    uint256 constant SDT_VALUE = 20 ether;
    uint256 constant INITIAL_ETH = 100 ether;

    uint256 public constant LOCK_TIME = 2592000;
    uint256 private constant QUARTERLY_LOCK = 7776000;
    uint256 private constant BIANNUAL_LOCK = 15552000;
    uint256 private constant ANNUAL_LOCK = 31104000;

    uint256 private constant REWARD_PERCENT = 1;
    uint256 private constant QUARTERLY_REWARD_PERCENT = 3;
    uint256 private constant BIANNUAL_REWARD_PERCENT = 5;
    uint256 private constant ANNUAL_REWARD_PERCENT = 8;
    uint256 private constant REWARD_PERCENT_PRECISION = 100;
    uint256 private constant PENALTY_FEE = 5;

    event SdtStaked(address indexed user, uint256 indexed value);
    event EthStaked(address indexed user, uint256 indexed amount);
    event EthUnstaked(address indexed user, uint256 indexed amount);
    event SdtUnstaked(address indexed user, uint256 indexed amount);
    event EthUnstakedForce(address indexed user, uint256 indexed amount, uint256 penaltyAmount);
    event SdtUnstakedForce(address indexed user, uint256 indexed amount, uint256 penaltyAmount);

    function setUp() external {
        deployer = new DeployStakeDrop();
        (token, stakeDrop) = deployer.run();

        vm.deal(USER, USER_BALANCE);
        vm.deal(address(stakeDrop), INITIAL_ETH);

        token.mint(USER, initialBalance);
        vm.prank(USER);
        IERC20(token).approve(address(stakeDrop), initialBalance);

        vm.prank(stakeDrop.owner());
        stakeDrop.transferOwnership(address(this));

        assertEq(stakeDrop.owner(), address(this));
    }

    /*////////////////////////////////////////////////////////////
                                ETH STAKE
    ////////////////////////////////////////////////////////////*/

    function testUserCanStakeEth() public {
        vm.prank(USER);
        stakeDrop.stakeEth{value: VALUE}();
    }

    function testStakeFailesWhenAmountIsZero() public {
        vm.expectRevert();
        vm.prank(USER);
        stakeDrop.stakeEth();
    }

    modifier ethStaked() {
        vm.prank(USER);
        stakeDrop.stakeEth{value: VALUE}();
        _;
    }

    function testUpdateStakedAmountAndStakeTimeWhenUserStakes() public ethStaked {
        StakeDropV1.Stake memory stake = stakeDrop.getUserStakes(USER);
        uint256 expectedAmount = VALUE;
        uint256 actualAmount = stake.ethAmount;

        uint256 lockTime = stakeDrop.getLockTime();
        uint256 expectedStakedTime = lockTime;
        uint256 actualStakedTime = stake.ethUserTimestamp;

        assertEq(actualAmount, expectedAmount);
        assertEq(actualStakedTime, expectedStakedTime);
    }

    function testStakedWithEthEmitsAnEvent() public {
        vm.expectEmit(true, true, false, true);
        emit EthStaked(USER, VALUE);

        vm.prank(USER);
        stakeDrop.stakeEth{value: VALUE}();
    }

    function testUserStatusChangesToTrueAfterStake() public ethStaked {
        assert(stakeDrop.getIfUserStakedEth(USER) == true);
    }

    /*////////////////////////////////////////////////////////////
                                SDT STAKE
    ////////////////////////////////////////////////////////////*/
    function testUserCanStakeSdt() public {
        vm.prank(USER);
        // token.approve(address(stakeDrop), initialBalance);
        stakeDrop.stakeSdt(SDT_VALUE);
    }

    modifier sdtStaked() {
        vm.prank(USER);
        stakeDrop.stakeSdt(SDT_VALUE);
        _;
    }

    function testUpdateSdtStakedAmountAndStakeTimeWhenUserStakes() public sdtStaked {
        StakeDropV1.Stake memory stake = stakeDrop.getUserStakes(USER);
        uint256 expectedAmount = SDT_VALUE;
        uint256 actualAmount = stake.sdtAmount;

        uint256 lockTime = stakeDrop.getLockTime();
        uint256 expectedTime = lockTime;
        uint256 actualTime = stake.sdtUserTimestamp;

        assertEq(actualAmount, expectedAmount);
        assertEq(actualTime, expectedTime);
    }

    function testStakedWithSdtEmitsAnEvent() public {
        vm.expectEmit(true, true, false, true);
        emit SdtStaked(USER, SDT_VALUE);

        vm.prank(USER);
        stakeDrop.stakeSdt(SDT_VALUE);
    }

    function testUserStatusChangesToTrueAfterStakeSdt() public sdtStaked {
        assert(stakeDrop.getIfUserStakedSdt(USER) == true);
    }

    /*////////////////////////////////////////////////////////////
                              ETH UNSTAKE
    ////////////////////////////////////////////////////////////*/
    function testUnstakeEthFailsIfUserDidntStake() public {
        vm.prank(USER);
        vm.expectRevert(StakeDropV1.StakeDropV1__NotStakedYet.selector);
        stakeDrop.unstake(VALUE, true);
    }

    function testUnstakeEthFailsIfUnstakeAmountBeMoreThanEthStakedAmount() public ethStaked {
        vm.prank(USER);
        vm.expectRevert(StakeDropV1.StakeDropV1__InvalidAmount.selector);
        stakeDrop.unstake(2 ether, true);
    }

    function testCantUnstakeSdtWithEth() public ethStaked {
        vm.prank(USER);
        vm.expectRevert();
        stakeDrop.unstake(VALUE, false);
    }

    function testUnstakeEthFailsIfTimeNotPassedYet() public ethStaked {
        vm.prank(USER);
        vm.expectRevert(StakeDropV1.StakeDropV1__StakeTimeNotPassed.selector);
        stakeDrop.unstake(VALUE, true);
    }

    function testUserCanUnstakeEth() public ethStaked {
        vm.warp(block.timestamp + LOCK_TIME + 1);
        vm.roll(block.number + 1);
        vm.prank(USER);
        stakeDrop.unstake(VALUE, true);
        
    }

    function testUserCanUnstakeDesiredEthAmount() public ethStaked {
        vm.warp(block.timestamp + LOCK_TIME + 1);
        vm.roll(block.number + 1);

        uint256 desiredAmount = 0.5 ether;

        vm.prank(USER);
        stakeDrop.unstake(desiredAmount, true);
    }

    function testUnstakeEthDeductsUserAmountAndTimeAfterUnstake() public ethStaked {
        StakeDropV1.Stake memory stake = stakeDrop.getUserStakes(USER);
        uint256 startingUserTime = stake.ethUserTimestamp;
        uint256 startingUserStakeAmount = stake.ethAmount;
        uint256 startingTime = LOCK_TIME;
        console2.log("startingUserTime :", startingUserTime);

        assertEq(startingUserTime, startingTime);
        assertEq(startingUserStakeAmount, VALUE);

        vm.warp(block.timestamp + LOCK_TIME + 1);
        vm.roll(block.number + 1);

        vm.prank(USER);
        stakeDrop.unstake(VALUE, true);

        uint256 endingUserTime = stake.ethUserTimestamp - startingTime;
        uint256 endingUserStakedAmount = stake.ethAmount - VALUE;
        console2.log("endingUserTime :", endingUserTime);
        console2.log("block.timestamp  :", block.timestamp);

        assertEq(endingUserTime, 0);
        assertEq(endingUserStakedAmount, 0);
    }

    function testUpdateUserStatusToFalseWhenUserUnsktakesWholeEthAmount() public ethStaked {
        vm.warp(block.timestamp + LOCK_TIME + 1);
        vm.roll(block.number + 1);

        vm.prank(USER);
        stakeDrop.unstake(VALUE, true);

        assertEq(stakeDrop.getIfUserStakedEth(USER), false);
    }

    function testUnstakeEthEmitsAnEvent() public ethStaked {
        vm.expectEmit(true, true, false, true);
        emit EthUnstaked(USER, VALUE);

        vm.warp(block.timestamp + LOCK_TIME + 1);
        vm.roll(block.number + 1);

        vm.prank(USER);
        stakeDrop.unstake(VALUE, true);
    }

    /*////////////////////////////////////////////////////////////
                              SDT UNSTAKE
    ////////////////////////////////////////////////////////////*/
    function testUnstakeSdtFailsIfUserDidntStake() public {
        vm.prank(USER);
        vm.expectRevert(StakeDropV1.StakeDropV1__NotStakedYet.selector);
        stakeDrop.unstake(SDT_VALUE, false);
    }

    function testUnstakeSdtFailsIfAmountBeGreaterThanStakedAmount() public sdtStaked {
        vm.warp(block.timestamp + LOCK_TIME + 1);
        vm.roll(block.number + 1);

        vm.prank(USER);
        vm.expectRevert();
        stakeDrop.unstake(100 ether, false);
    }

    function testUnstakeSdtFailsIfTimeDidntPass() public sdtStaked {
        vm.prank(USER);
        vm.expectRevert();
        stakeDrop.unstake(SDT_VALUE, false);
    }

    modifier timePassed() {
        vm.warp(block.timestamp + LOCK_TIME + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testUserCanUnstakeDesiredSdtAmount() public sdtStaked timePassed {
        uint256 startingUserBalance = token.balanceOf(USER);

        uint256 desiredSdtAmount = 10 ether;
        vm.prank(USER);
        stakeDrop.unstake(desiredSdtAmount, false);

        uint256 endingUserBalance = token.balanceOf(USER);

        assertEq(startingUserBalance, initialBalance - SDT_VALUE);
        assertEq(endingUserBalance, startingUserBalance + desiredSdtAmount);
    }

    function testDeleteUserStatusAndUserTimeAndUserAmountStakedWhenUserUnstakesAllSdtStaked()
        public
        sdtStaked
        timePassed
    {
        console2.log("staked sdt %s ", SDT_VALUE);
        StakeDropV1.Stake memory stake = stakeDrop.getUserStakes(USER);
        vm.prank(USER);
        stakeDrop.unstake(SDT_VALUE, false);

        // uint256 endingTime = block.timestamp - 1;
        uint256 userSdtStakedAmount = stake.sdtAmount - SDT_VALUE;
        console2.log("userSdtStakedAmountstaked sdt %s ", userSdtStakedAmount);
        uint256 userTimeStake = stake.sdtUserTimestamp - LOCK_TIME;

        assertEq(userSdtStakedAmount, 0);
        assertEq(userTimeStake, 0);
    }

    function testUserStatusChangesToFalseWhenUserUnstakeAllSdtStaked() public sdtStaked timePassed {
        vm.prank(USER);
        stakeDrop.unstake(SDT_VALUE, false);

        assertEq(stakeDrop.getIfUserStakedSdt(USER), false);
    }

    function testUnstakeSdtEmitsAnEvent() public sdtStaked timePassed {
        vm.expectEmit(true, true, false, true);
        emit SdtUnstaked(USER, SDT_VALUE);

        vm.prank(USER);
        stakeDrop.unstake(SDT_VALUE, false);
    }

    /*////////////////////////////////////////////////////////////
                          ETH FORCE UNSTAKE
    ////////////////////////////////////////////////////////////*/
    function testPenaltyCalculatesCorrectly() public view {
        uint256 penaltyFee = 5;
        uint256 feePrecision = 100;
        uint256 calculatePenalty = (VALUE * penaltyFee) / feePrecision;
        uint256 expectedPenalty = 0.05 ether;

        uint256 actualPenalty = stakeDrop.getPenaltyAmount(VALUE);
        console2.log("penalty amount %s ", actualPenalty);

        assert(expectedPenalty == calculatePenalty);
        assert(actualPenalty == expectedPenalty);
    }

    function testForceUnstakeEthFailsIfUserDidtStake() public {
        vm.prank(USER);
        vm.expectRevert(StakeDropV1.StakeDropV1__NotStakedYet.selector);
        stakeDrop.forceUnstake(VALUE, true);
    }

    function testForceUnstakeEthFailsIfUnstakeAmountBeGreaterThanStakedEth() public ethStaked {
        vm.prank(USER);
        vm.expectRevert();
        stakeDrop.forceUnstake(2 ether, true);
    }

    function testUserCanForceUnstakeDesiredEthAmountAndPaysThePenalty() public ethStaked {
        uint256 desiredAmount = VALUE / 2;
        uint256 penaltyFee = 5;
        uint256 feePrecision = 100;
        uint256 expectedPenalty = (desiredAmount * penaltyFee) / feePrecision;
        console2.log("desiredAmount %s ", desiredAmount);

        vm.prank(USER);
        stakeDrop.forceUnstake(desiredAmount, true);

        uint256 actualPenalty = stakeDrop.getPenaltyAmount(desiredAmount);

        uint256 expectedUnstakedAmount = desiredAmount - expectedPenalty;
        uint256 actualUnstakedAmount = desiredAmount - actualPenalty;
        console2.log("Unstaked Amount %s ", actualUnstakedAmount);

        assertEq(actualUnstakedAmount, expectedUnstakedAmount);
    }

    function testDeleteEthAmountStakedAndUserTimeAndChangeUserStatusToFalseAndPenaltyPaidWhenUserForceUnstakeAllEthAmount(
    ) public ethStaked {
        StakeDropV1.Stake memory stake = stakeDrop.getUserStakes(USER);
        vm.prank(USER);
        stakeDrop.forceUnstake(VALUE, true);
        console2.log(" user timestamp %s ", stake.ethUserTimestamp);

        uint256 userTimestamp = LOCK_TIME;
        uint256 userTime = stake.ethUserTimestamp - userTimestamp;

        assertEq(userTime, 0);

        uint256 penaltyFee = 5;
        uint256 feePrecision = 100;
        uint256 expectedPenalty = (VALUE * penaltyFee) / feePrecision;
        uint256 finalAmount = VALUE - expectedPenalty;

        uint256 userStakeEthAmount = stake.ethAmount - finalAmount;
        uint256 contractBalance = token.balanceOf(address(stakeDrop));
        uint256 finalContractBalance = contractBalance + expectedPenalty;
        console2.log("Contract Balance %s ", finalContractBalance);

        uint256 finalStakedAmount = stake.ethAmount - VALUE;

        assertEq(userStakeEthAmount, expectedPenalty);
        assertEq(finalContractBalance, contractBalance + expectedPenalty);
        assertEq(finalStakedAmount, 0);

        bool userStatus = stakeDrop.getIfUserStakedEth(USER);

        assertEq(userStatus, false);
    }

    function testForceUnstakeEthEmitsAnEvent() public ethStaked {
        uint256 penaltyFee = 5;
        uint256 feePrecision = 100;
        uint256 penalty = (VALUE * penaltyFee) / feePrecision;

        vm.expectEmit(true, true, false, true);
        emit EthUnstakedForce(USER, VALUE, penalty);

        vm.prank(USER);
        stakeDrop.forceUnstake(VALUE, true);
    }

    /*////////////////////////////////////////////////////////////
                          SDT FORCE UNSTAKE
    ////////////////////////////////////////////////////////////*/
    function testForceUnstakeSdtFailsIfUserDidtStake() public {
        vm.prank(USER);
        vm.expectRevert(StakeDropV1.StakeDropV1__NotStakedYet.selector);
        stakeDrop.forceUnstake(SDT_VALUE, false);
    }

    function testForceUnstakeSdtFailsIfUnstakeAmountBeGreaterThanStakedSdt() public sdtStaked {
        vm.prank(USER);
        vm.expectRevert();
        stakeDrop.forceUnstake(100 ether, false);
    }

    function testUserCanForceUnstakeDesiredSdtAmountAndPaysThePenalty() public sdtStaked {
        uint256 desiredAmount = SDT_VALUE / 2;
        uint256 penaltyFee = 5;
        uint256 feePrecision = 100;
        uint256 expectedPenalty = (desiredAmount * penaltyFee) / feePrecision;

        vm.prank(USER);
        stakeDrop.forceUnstake(desiredAmount, false);

        uint256 actualPenalty = stakeDrop.getPenaltyAmount(desiredAmount);

        uint256 expectedUnstakedAmount = desiredAmount - expectedPenalty;
        uint256 actualUnstakedAmount = desiredAmount - actualPenalty;

        assertEq(actualUnstakedAmount, expectedUnstakedAmount);
    }

    function testDeleteSdtAmountStakedAndUserTimeAndChangeUserStatusToFalseAndPenaltyPaidWhenUserForceUnstakeAllSdtAmount(
    ) public sdtStaked {
        StakeDropV1.Stake memory stake = stakeDrop.getUserStakes(USER);
        vm.prank(USER);
        stakeDrop.forceUnstake(SDT_VALUE, false);

        uint256 userTimestamp = LOCK_TIME;
        uint256 userTime = stake.sdtUserTimestamp - userTimestamp;

        assertEq(userTime, 0);

        uint256 penaltyFee = 5;
        uint256 feePrecision = 100;
        uint256 expectedPenalty = (SDT_VALUE * penaltyFee) / feePrecision;
        uint256 finalAmount = SDT_VALUE - expectedPenalty;

        uint256 userStakeSdtAmount = stake.sdtAmount - finalAmount;
        uint256 contractBalance = token.balanceOf(address(stakeDrop));
        uint256 finalContractBalance = contractBalance + expectedPenalty;

        uint256 finalStakedAmount = stake.sdtAmount - SDT_VALUE;

        assertEq(userStakeSdtAmount, expectedPenalty);
        assertEq(finalContractBalance, contractBalance + expectedPenalty);
        assertEq(finalStakedAmount, 0);

        bool userStatus = stakeDrop.getIfUserStakedSdt(USER);

        assertEq(userStatus, false);
    }

    function testForceUnstakeSdtEmitsAnEvent() public sdtStaked {
        uint256 penaltyFee = 5;
        uint256 feePrecision = 100;
        uint256 penalty = (SDT_VALUE * penaltyFee) / feePrecision;

        vm.expectEmit(true, true, false, true);
        emit SdtUnstakedForce(USER, SDT_VALUE, penalty);

        vm.prank(USER);
        stakeDrop.forceUnstake(SDT_VALUE, false);
    }

    /*////////////////////////////////////////////////////////////
                                REWARDS
    ////////////////////////////////////////////////////////////*/
    function testEthRewardsCalculateCorrectAnswers() public pure {

        uint256 normalReward = (VALUE * REWARD_PERCENT) / REWARD_PERCENT_PRECISION;
        uint256 quarterlyReward = (VALUE * QUARTERLY_REWARD_PERCENT) / REWARD_PERCENT_PRECISION;
        uint256 biannualReward = (VALUE * BIANNUAL_REWARD_PERCENT) / REWARD_PERCENT_PRECISION;
        uint256 annualReward = (VALUE * ANNUAL_REWARD_PERCENT) / REWARD_PERCENT_PRECISION;

        assert(normalReward == 0.01 ether);
        assert(quarterlyReward == 0.03 ether);
        assert(biannualReward == 0.05 ether);
        assert(annualReward == 0.08 ether);
    }

    function testClaimEthRewardFailsIfUserDidntStake() public {
        vm.prank(USER);
        vm.expectRevert(StakeDropV1.StakeDropV1__NotStakedYet.selector);
        stakeDrop.claimReward(USER, true);
    }

    function testClaimEthRewardFailsIfTimeNotPassed() public ethStaked {
        vm.prank(USER);
        vm.expectRevert(StakeDropV1.StakeDropV1__StakeTimeNotPassed.selector);
        stakeDrop.claimReward(USER, true);
    }

    function testUserCanClaimEthReward() public ethStaked timePassed {
        vm.prank(USER);
        stakeDrop.claimReward(USER, true);
    }

    function testUserCnatClaimRewardIfAlreadyClaimed() public  {

        vm.startPrank(USER);
        stakeDrop.stakeEth{value: VALUE}();
        vm.stopPrank();

        vm.warp(block.timestamp + LOCK_TIME + 1);
        vm.roll(block.number + 1);

        vm.startPrank(USER);
        stakeDrop.claimReward(USER, true);
        vm.stopPrank();

        vm.startPrank(USER);
        vm.expectRevert(StakeDropV1.StakeDropV1__NoRewardsToClaim.selector);
        stakeDrop.claimReward(USER, true);
        vm.stopPrank();
    }

    function testEthUserCanClaimRewardInDifferentIntervals() public ethStaked  {
        vm.startPrank(USER);
        vm.warp(block.timestamp + QUARTERLY_LOCK - 1);
        vm.roll(block.number + 1);
        uint256 normalReward = (VALUE * REWARD_PERCENT) / REWARD_PERCENT_PRECISION;
        stakeDrop.claimReward(USER, true);
        vm.stopPrank();

        uint256 expectedUserBalanceAfterNormalReward = USER_BALANCE + normalReward;
        uint256 actualUserBalanceAfterNormalReward = token.balanceOf(USER) + normalReward;

        vm.startPrank(USER);
        stakeDrop.stakeEth{value: VALUE}();


        vm.warp(block.timestamp + BIANNUAL_LOCK - 1);
        vm.roll(block.number + 1);
        uint256 quarterlyReward = (VALUE * QUARTERLY_REWARD_PERCENT) / REWARD_PERCENT_PRECISION;
        stakeDrop.claimReward(USER, true);
        vm.stopPrank();

        uint256 expectedUserBalanceAfterQuarterlyReward = USER_BALANCE + quarterlyReward;
        uint256 actualUserBalanceAfterQuarterlyReward = token.balanceOf(USER) + quarterlyReward;

        vm.startPrank(USER);
        stakeDrop.stakeEth{value: VALUE}();


        vm.warp(block.timestamp + ANNUAL_LOCK - 1);
        vm.roll(block.number + 1);
        uint256 biannualReward = (VALUE * BIANNUAL_REWARD_PERCENT) / REWARD_PERCENT_PRECISION;
        stakeDrop.claimReward(USER, true);
        vm.stopPrank();

        uint256 expectedUserBalanceAfterBiannualReward = USER_BALANCE + biannualReward;
        uint256 actualUserBalanceAfterBiannualReward = token.balanceOf(USER) + biannualReward;

        vm.startPrank(USER);
        stakeDrop.stakeEth{value: VALUE}();


        vm.warp(block.timestamp + ANNUAL_LOCK + 1);
        vm.roll(block.number + 1);
        uint256 annualReward = (VALUE * ANNUAL_REWARD_PERCENT) / REWARD_PERCENT_PRECISION;
        stakeDrop.claimReward(USER, true);
        vm.stopPrank();

        uint256 expectedUserBalanceAfterAnnualReward = USER_BALANCE + annualReward;
        uint256 actualUserBalanceAfterAnnualReward = token.balanceOf(USER) + annualReward;

        assertEq(actualUserBalanceAfterNormalReward, expectedUserBalanceAfterNormalReward);
        assertEq(actualUserBalanceAfterQuarterlyReward, expectedUserBalanceAfterQuarterlyReward);
        assertEq(actualUserBalanceAfterBiannualReward, expectedUserBalanceAfterBiannualReward);
        assertEq(actualUserBalanceAfterAnnualReward, expectedUserBalanceAfterAnnualReward);
    }

    /*////////////////////////////////////////////////////////////
                                RECOVER
    ////////////////////////////////////////////////////////////*/
    function testOwnerCanRecoverSdt() public {
        vm.prank(token.owner());
        stakeDrop.recoverSdt(50 ether);
    }

    function testOwnerCanRecoverEth() public {
        vm.prank(token.owner());
        stakeDrop.recoverSdt(1 ether);
    }

    function testRecoverSdtFalisIfNotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        stakeDrop.recoverSdt(50 ether);
    }

    function testRecoverEthFalisIfNotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        stakeDrop.recoverSdt(1 ether);
    } 

    function testRecoverSdtFailsIfCotractHasNoEnoughBalance() public {
        vm.prank(token.owner());
        vm.expectRevert(StakeDropV1.StakeDropV1__ContractHasNoEnoughBalance.selector);
        stakeDrop.recoverSdt(101 ether);
    }

    function testRecoverEthFailsIfCotractHasNoEnoughBalance() public {
        vm.prank(token.owner());
        vm.expectRevert(StakeDropV1.StakeDropV1__ContractHasNoEnoughBalance.selector);
        stakeDrop.recoverSdt(101 ether);
    }

   /*////////////////////////////////////////////////////////////
                                GETTERS
    ////////////////////////////////////////////////////////////*/
    function testGetIfUserStakedEthFunctionWorksWell() public ethStaked {
        assert(stakeDrop.getIfUserStakedEth(USER) == true);
        assert(stakeDrop.getIfUserStakedSdt(USER) == false);

    }

    function testGetIfUserStakedSdtFunctionWorksWell() public sdtStaked {
        assert(stakeDrop.getIfUserStakedEth(USER) == false);
        assert(stakeDrop.getIfUserStakedSdt(USER) == true);

    }

    function testGetIfUserStakedSdtAndEthFunctionsWorkWell() public ethStaked sdtStaked {
        assert(stakeDrop.getIfUserStakedEth(USER) == true);
        assert(stakeDrop.getIfUserStakedSdt(USER) == true);

    }

    function testGetIfUsersClaimedEthRewardsWorks() public ethStaked timePassed{
        vm.prank(USER);
        stakeDrop.claimReward(USER, true);

        uint256 reward = (VALUE * REWARD_PERCENT) / REWARD_PERCENT_PRECISION;

        assertEq(stakeDrop.getIfUsersClaimedEthRewards(USER,reward), true);
    }

    function testGetIfUsersClaimedSdtRewardsWorks() public sdtStaked timePassed{
        vm.prank(USER);
        stakeDrop.claimReward(USER, false);

        uint256 reward = (SDT_VALUE * REWARD_PERCENT) / REWARD_PERCENT_PRECISION;

        assertEq(stakeDrop.getIfUsersClaimedSdtRewards(USER,reward), true);
    }

    function testGetIfUsersClaimedEthQuarterlyReward() public ethStaked  {

       uint256 quarterlyReward = (VALUE * QUARTERLY_REWARD_PERCENT) / REWARD_PERCENT_PRECISION;
    
        vm.warp(block.timestamp + BIANNUAL_LOCK - 1);
        vm.roll(block.number + 1);
        vm.prank(USER);
        stakeDrop.claimReward(USER, true);
         
        assertEq(stakeDrop.getIfUsersClaimedEthRewards(USER,quarterlyReward), true);

    }

    function testGetIfUsersClaimedEthBiannualReward() public ethStaked  {
        uint256 biannualReward = (VALUE * BIANNUAL_REWARD_PERCENT) / REWARD_PERCENT_PRECISION;

        vm.warp(block.timestamp + ANNUAL_LOCK - 1);
        vm.roll(block.number + 1);
        vm.prank(USER);
        stakeDrop.claimReward(USER, true);

        assertEq(stakeDrop.getIfUsersClaimedEthRewards(USER,biannualReward), true);

    }
    function testGetIfUsersClaimedEthAnnualReward() public ethStaked  {


        uint256 annualReward = (VALUE * ANNUAL_REWARD_PERCENT) / REWARD_PERCENT_PRECISION;
        

        vm.warp(block.timestamp + ANNUAL_LOCK + LOCK_TIME);
        vm.roll(block.number + 1);
        vm.prank(USER);
        stakeDrop.claimReward(USER, true);

        assertEq(stakeDrop.getIfUsersClaimedEthRewards(USER,annualReward), true);

    }

    function testGetIfUsersClaimedSdtQuarterlyReward() public sdtStaked  {

       uint256 quarterlyReward = (SDT_VALUE * QUARTERLY_REWARD_PERCENT) / REWARD_PERCENT_PRECISION;
    
        vm.warp(block.timestamp + BIANNUAL_LOCK - 1);
        vm.roll(block.number + 1);
        vm.prank(USER);
        stakeDrop.claimReward(USER, false);
         
        assertEq(stakeDrop.getIfUsersClaimedSdtRewards(USER,quarterlyReward), true);

    }

    function testGetIfUsersClaimedSdtBiannualReward() public sdtStaked  {
        uint256 biannualReward = (SDT_VALUE * BIANNUAL_REWARD_PERCENT) / REWARD_PERCENT_PRECISION;

        console2.log("Before warp: ", block.timestamp);
        vm.warp(block.timestamp + ANNUAL_LOCK - 1);
        console2.log("after warp ", block.timestamp );
        vm.roll(block.number + 1);
        vm.prank(USER);
        stakeDrop.claimReward(USER, false);
    


        assertEq(stakeDrop.getIfUsersClaimedSdtRewards(USER,biannualReward), true);

    }
    function testGetIfUsersClaimedSdtAnnualReward() public sdtStaked  {


        uint256 annualReward = (SDT_VALUE * ANNUAL_REWARD_PERCENT) / REWARD_PERCENT_PRECISION;
        

        vm.warp(block.timestamp + ANNUAL_LOCK + LOCK_TIME);
        vm.roll(block.number + 1);
        vm.prank(USER);
        stakeDrop.claimReward(USER, false);

        assertEq(stakeDrop.getIfUsersClaimedSdtRewards(USER,annualReward), true);

    }

    function testLockTimeReturnsCorrectAnswer() public view{
        uint256 expectedTime = LOCK_TIME;
        uint256 actualTime = stakeDrop.getLockTime();

        assert(actualTime == expectedTime);
    }

    function testGetPenaltyAmountReturnsCorrectAnswer() public view{
        
        uint256 feePrecision = 100;
        uint256 expectedPenalty = (VALUE * PENALTY_FEE) / feePrecision;
        uint256 actualPenalty = stakeDrop.getPenaltyAmount(VALUE);

        assert(actualPenalty == expectedPenalty);
    }

    function testGetpenaltyFeeReturnsCorrectAnswer() public view{
        uint256 expectedFee = PENALTY_FEE;
        uint256 actualFee = stakeDrop.getpenaltyFee();

        assert(actualFee == expectedFee);
    }

    function testGetQuarterlyAndBiannualAndAnnualLockDurationReturnsCorrectAnswers() public view{
        uint256 expectedQuarterlyDuration = QUARTERLY_LOCK;
        uint256 actualQuarterlyDuration = stakeDrop.getQuarterlyLockDuration();

        uint256 expectedBiannualDuration = BIANNUAL_LOCK;
        uint256 actualBiannualDuration = stakeDrop.getBiannualLockDuration();

        uint256 expectedAnnualDuration = ANNUAL_LOCK;
        uint256 actualAnnualDuration = stakeDrop.getAnnualLockDuration();

        assert(actualQuarterlyDuration == expectedQuarterlyDuration);
        assert(actualBiannualDuration == expectedBiannualDuration);
        assert(actualAnnualDuration == expectedAnnualDuration);
    }

    function testGetDifferentRewardPercentsAndPercentPrecisionWorkCorrect() public view{
        uint256 expectedNormalRewardPercent = REWARD_PERCENT;
        uint256 actualNormalRewardPercent = stakeDrop.getNormalRewardPercent();

        uint256 expectedQuarterlyRewardPercent = QUARTERLY_REWARD_PERCENT;
        uint256 actualQuarterlyRewardPercent = stakeDrop.getQuarterlyRewardPercent();

        uint256 expectedBiannualRewardPercent = BIANNUAL_REWARD_PERCENT;
        uint256 actualBiannualRewardPercent = stakeDrop.getBiannualRewardPercent();

        uint256 expectedAnnualRewardPercent = ANNUAL_REWARD_PERCENT;
        uint256 actualAnnualRewardPercent = stakeDrop.getAnnualRewardPercent();

        uint256 expectedRewardPercentPrecision = REWARD_PERCENT_PRECISION;
        uint256 actualRewardPercentPrecision = stakeDrop.getRewardPercentPrecision();

        assert(actualNormalRewardPercent == expectedNormalRewardPercent);
        assert(actualQuarterlyRewardPercent == expectedQuarterlyRewardPercent);
        assert(actualBiannualRewardPercent == expectedBiannualRewardPercent);
        assert(actualAnnualRewardPercent == expectedAnnualRewardPercent);
        assert(actualRewardPercentPrecision == expectedRewardPercentPrecision);
    }

    function testGetContractBalanceReturnsCorrectBalance() public view{
        uint256 expectedBalance = initialBalance;
        uint256 actualBalance = address(stakeDrop).balance;

        assert(actualBalance == expectedBalance);
    }
}
