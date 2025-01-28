// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {StakeDropAirdrop} from "../../../src/StakeDropAirdrop.sol";
import {StakeDropToken} from "../../../src/StakeDropToken.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";

contract DeployStakeDropAirdrop is Script {
    bytes32 constant ROOT = 0x11c587a8c8062806c45063501655e511f728c6ee964718e02f9c500c884fbee2;
    uint256 constant AMOUNT_TO_SEND = 10 * 100e18;

    function run() external returns (StakeDropAirdrop, StakeDropToken) {
        return deployAirdrop();
    }

    function deployAirdrop() public returns (StakeDropAirdrop, StakeDropToken) {
        vm.startBroadcast();
        StakeDropToken token = new StakeDropToken();
        StakeDropAirdrop airdrop = new StakeDropAirdrop(ROOT, IERC20(token));
        token.mint(token.owner(), AMOUNT_TO_SEND);
        IERC20(token).transfer(address(airdrop), AMOUNT_TO_SEND);
        vm.stopBroadcast();

        return (airdrop, token);
    }
}
