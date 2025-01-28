// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console2} from "forge-std/Test.sol";
import {StakeDropToken} from "../../src/StakeDropToken.sol";
import {StakeDropAirdrop} from "../../src/StakeDropAirdrop.sol";
import {DeployStakeDropAirdrop} from "../../script/Airdrop/target/DeployStakeDropAirdrop.s.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";

contract StakeDropAirdropTest is Test {
    DeployStakeDropAirdrop deployer;
    StakeDropToken token;
    StakeDropAirdrop airdrop;

    bytes32 public constant ROOT = 0x11c587a8c8062806c45063501655e511f728c6ee964718e02f9c500c884fbee2;

    bytes32 public proof_one = 0x91ca955de9f6cc63db9e7369302acfbbd2c9c7ca7c6d3cc8cf9c9acaead52c6c;
    bytes32 public proof_two = 0x118bf10c3828a1483f8716aea0b41cc5806780b3078c2baf804844325423a6dc;
    bytes32 public proof_three = 0xf7c64a5cb4e8581c57e9221b8ba8ec5dd08293e639318f620a8c5cde0a4b2180;
    bytes32 public proof_four = 0x89d48911a6a371387e29b1b976da61b06b9c09846ce23c496c7ac20c5560c8e0;

    bytes32 public invalid_proof_one = 0x297c265b7d94f090388308bf6d31ab83b84b3e671064deec227dedd598041a49;
    bytes32 public invalid_proof_two = 0x711fdde2223ff9a10eb9ea858755eb9bc6195bf20806e67451736d5b031aa611;
    bytes32 public invalid_proof_three = 0xb429e2bc531ad3fb152713154de3bc6f75ea6dbceb34d3697da8a361fed1931b;
    bytes32 public invalid_proof_four = 0x25b4affbd8417014bc5d4c34eedabe9aec66119f81c7ffdbfb126c9d8a0eebdb;

    bytes32[] public proof = [proof_one, proof_two, proof_three, proof_four];

    bytes32[] public invalid_proof = [invalid_proof_one, invalid_proof_two, invalid_proof_three, invalid_proof_four];

    address claimer;
    address gasPayer;
    uint256 claimAmount = 100e18;
    uint256 amountToSend = claimAmount * 10;
    uint256 claimerPrivateKey;

    function setUp() public {
        deployer = new DeployStakeDropAirdrop();
        token = new StakeDropToken();
        airdrop = new StakeDropAirdrop(ROOT, token);

        token.mint(token.owner(), amountToSend);
        token.transfer(address(airdrop), amountToSend);

        (claimer, claimerPrivateKey) = makeAddrAndKey("user");
        gasPayer = makeAddr("gasPayer");
    }

    function signMessage(address account, uint256 privKey) public view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 hashedMessage = airdrop.getMessageHash(account, claimAmount);
        (v, r, s) = vm.sign(privKey, hashedMessage);
    }

    function testConstructorInitializesRootAndToken() public view {
        bytes32 expectedRoot = ROOT;
        bytes32 actualRoot = airdrop.getMerkleRoot();

        IERC20 expectedToken = IERC20(token);
        IERC20 actualToken = airdrop.getAirdropToken();

        assertEq(actualRoot, expectedRoot);
        assert(actualToken == expectedToken);
    }

    function testUserCanSignAndClaimAirdrop() public {
        vm.prank(claimer);
        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = signMessage(claimer, claimerPrivateKey);

        airdrop.claimAirdrop(claimer, claimAmount, proof, v, r, s);
    }

    function testClaimAirdropFailsIfClaimerAlreadyClaimed() public {
        vm.startPrank(claimer);
        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = signMessage(claimer, claimerPrivateKey);

        airdrop.claimAirdrop(claimer, claimAmount, proof, v, r, s);
        vm.stopPrank();

        vm.prank(claimer);
        vm.expectRevert(StakeDropAirdrop.StakeDropAirdrop__AlreadyClaimed.selector);
        airdrop.claimAirdrop(claimer, claimAmount, proof, v, r, s);
    }

    function testClaimAirdropFailsIfSignatureNotValid() public {
        vm.prank(gasPayer);
        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = signMessage(gasPayer, claimerPrivateKey);

        vm.expectRevert(StakeDropAirdrop.StakeDropAirdrop__InvalidSignature.selector);
        airdrop.claimAirdrop(gasPayer, claimAmount, proof, v, r, s);
    }

    function testClaimAirdropFailsIfProofNotValid() public {
        vm.prank(claimer);
        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = signMessage(claimer, claimerPrivateKey);

        vm.expectRevert(StakeDropAirdrop.StakeDropAirdrop__InvalidProof.selector);
        airdrop.claimAirdrop(claimer, claimAmount, invalid_proof, v, r, s);
    }

    function testClamerStatusChangesToTrueWhenClaim() public {
        vm.prank(claimer);
        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = signMessage(claimer, claimerPrivateKey);

        airdrop.claimAirdrop(claimer, claimAmount, proof, v, r, s);

        assert(airdrop.getIfUserHasClaimedAirdrop(claimer) == true);
    }

    function testGasPayerCanPayTheGasForClaimer() public {
        vm.prank(gasPayer);
        (uint8 v, bytes32 r, bytes32 s) = signMessage(claimer, claimerPrivateKey);

        airdrop.claimAirdrop(claimer, claimAmount, proof, v, r, s);
    }
}
