// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {StakeDropToken} from "../../src/StakeDropToken.sol";
import {StakeDropV1} from "../../src/StakeDrop.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";

contract DeployStakeDrop is Script {
    uint256 constant TOKENS_TO_SEND = 10000000e18;

    function run() external returns (StakeDropToken, StakeDropV1) {
        return deployStakeDrop();
    }

    function deployStakeDrop() public returns (StakeDropToken, StakeDropV1) {
        vm.startBroadcast();
        StakeDropToken token = new StakeDropToken();
        StakeDropV1 stakeDrop = new StakeDropV1(IERC20(token));
        token.mint(token.owner(), TOKENS_TO_SEND);
        IERC20(token).transfer(address(stakeDrop), TOKENS_TO_SEND);
        token.approve(address(stakeDrop), TOKENS_TO_SEND);
        token.transferOwnership(msg.sender);
        vm.stopBroadcast();

        return (token, stakeDrop);
    }
}
