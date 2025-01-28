// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {StakeDropToken} from "../../../src/StakeDropToken.sol";
import {StakeDropV1} from "../../../src/StakeDrop.sol";
import {DeployStakeDrop} from "../../../script/StakeDrop/DeployStakeDrop.s.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";

contract StopOnRevertInvariants is StdInvariant, Test{
    DeployStakeDrop deployer;
    StakeDropToken token;
    StakeDropV1 stakeDrop;

     address USER = makeAddr("user");
    uint256 constant USER_BALANCE = 100 ether;
    uint256 constant VALUE = 1 ether;
    uint256 initialBalance = 100 ether;
    uint256 constant SDT_VALUE = 20 ether;

    function setUp() external {
        deployer = new DeployStakeDrop();
        (token, stakeDrop) = deployer.run();

        vm.deal(USER, USER_BALANCE);

        token.mint(USER, initialBalance);
        vm.prank(USER);
        IERC20(token).approve(address(stakeDrop), initialBalance);

        vm.prank(stakeDrop.owner());
        stakeDrop.transferOwnership(address(this));

        assertEq(stakeDrop.owner(), address(this));
    }

    function invariant_gettersCantRevert() public view {
        stakeDrop.getLockTime();
        stakeDrop.getpenaltyFee();
        stakeDrop.getQuarterlyLockDuration();
        stakeDrop.getBiannualLockDuration();
        stakeDrop.getAnnualLockDuration();
        stakeDrop.getNormalRewardPercent();
        stakeDrop.getQuarterlyRewardPercent();
        stakeDrop.getBiannualRewardPercent();
        stakeDrop.getAnnualRewardPercent();
        stakeDrop.getRewardPercentPrecision();
        stakeDrop.getIfUserStakedEth(USER);
        stakeDrop.getIfUserStakedSdt(USER);
        stakeDrop.getIfUsersClaimedEthRewards(USER,VALUE);
        stakeDrop.getIfUsersClaimedSdtRewards(USER, VALUE);
        stakeDrop.getPenaltyAmount(VALUE);
    }
}