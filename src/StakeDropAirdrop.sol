// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {EIP712} from "@openzeppelin-contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import {MerkleProof} from "@openzeppelin-contracts/utils/cryptography/MerkleProof.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";


/**
 * @title StakeDropAirdrop
 * @author ArefXV
 * @dev This contract manages the distribution of token airdrops based on Merkle proofs and EIP-712 signatures
 *      Users must provide valid Merkle proofs and signatures to claim their airdrop rewards
 * @notice Implements protection against reentrancy attacks and ensures each user can claim the airdrop only once
 */
contract StakeDropAirdrop is EIP712, ReentrancyGuard {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;
    using MerkleProof for bytes32;
    
    /*///////////////////////////////////////////////////////
                              ERRORS
    ///////////////////////////////////////////////////////*/
    error StakeDropAirdrop__InvalidSignature();
    error StakeDropAirdrop__InvalidProof();
    error StakeDropAirdrop__AlreadyClaimed();

    /*///////////////////////////////////////////////////////
                              TYPES
    ///////////////////////////////////////////////////////*/
    /// @notice Represents an airdrop claim request
    struct ClaimAirdrop {
        address account;
        uint256 amount;
    }

    /*///////////////////////////////////////////////////////
                          STATE VARIABLES
    ///////////////////////////////////////////////////////*/
    /// @dev Keccak256 hash of the EIP-712 type for airdrop claims
    bytes32 private constant MESSAGE_TYPEHASH = keccak256("ClaimAirdrop(address account, uint256 amount)");

    /// @dev Immutable Merkle root used to validate user claims
    bytes32 private immutable i_merkleRoot;

    /// @dev Tracks whether a user has already claimed their airdrop
    mapping(address => bool) private s_hasClaimedAirdrop;

    /// @dev ERC20 token distributed as the airdrop
    IERC20 private immutable i_airdropToken;

    /*///////////////////////////////////////////////////////
                              EVENTS
    ///////////////////////////////////////////////////////*/
    /// @notice Event emitted when a user successfully claims an airdrop
    /// @param user The address of the user who claimed the airdrop
    /// @param amount The amount of tokens claimed by the user
    event AirdropClaimed(address indexed user, uint256 indexed amount);

    /*///////////////////////////////////////////////////////
                              FUNCTIONS
    ///////////////////////////////////////////////////////*/

    /**
     * @dev Constructor for the StakeDropAirdrop contract
     * @param merkleRoot The Merkle root used to validate user claims
     * @param airdropToken The ERC20 token distributed as the airdrop reward
     */
    constructor(bytes32 merkleRoot, IERC20 airdropToken) EIP712("Stake Drop Airdrop", "1.0.0") {
        i_merkleRoot = merkleRoot;
        i_airdropToken = airdropToken;
    }

    /*///////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////*/

    /**
     * @notice Allows a user to claim their airdrop
     * @dev Requires a valid Merkle proof and EIP-712 signature
     * @param account The address of the user claiming the airdrop
     * @param amount The amount of tokens to be claimed
     * @param merkleProof The Merkle proof to validate the claim
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature
     * @param s Half of the ECDSA signature
     * @custom:throws StakeDropAirdrop__AlreadyClaimed if the user has already claimed the airdrop.
     * @custom:throws StakeDropAirdrop__InvalidSignature if the provided signature is invalid.
     * @custom:throws StakeDropAirdrop__InvalidProof if the provided Merkle proof is invalid.
     */
    function claimAirdrop(
        address account,
        uint256 amount,
        bytes32[] calldata merkleProof,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        if (s_hasClaimedAirdrop[account]) {
            revert StakeDropAirdrop__AlreadyClaimed();
        }

        if (!_isValidSignature(account, (getMessageHash(account, amount)), v, r, s)) {
            revert StakeDropAirdrop__InvalidSignature();
        }

        if (!_isValidProof(account, amount, merkleProof)) {
            revert StakeDropAirdrop__InvalidProof();
        }

        s_hasClaimedAirdrop[account] = true;
        i_airdropToken.safeTransfer(account, amount);
        
    }

    /*///////////////////////////////////////////////////////
                          PUBLIC FUNCTIONS
    ///////////////////////////////////////////////////////*/

    /**
     * @notice Computes the EIP-712 message hash for a claim.
     * @param account The address of the user claiming the airdrop.
     * @param amount The amount of tokens to be claimed.
     * @return The computed message hash.
     */
    function getMessageHash(address account, uint256 amount) public view returns (bytes32) {
        return
            _hashTypedDataV4(keccak256(abi.encode(MESSAGE_TYPEHASH, ClaimAirdrop({account: account, amount: amount}))));
    }

    /*///////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////*/
    /**
     * @dev Validates the signature for a claim.
     * @param signer The expected signer of the claim.
     * @param digest The EIP-712 hash of the claim.
     * @param v The recovery byte of the signature.
     * @param r Half of the ECDSA signature.
     * @param s Half of the ECDSA signature.
     * @return True if the signature is valid, false otherwise.
     */
    function _isValidSignature(address signer, bytes32 digest, uint8 v, bytes32 r, bytes32 s)
        internal
        pure
        returns (bool)
    {
        (address actualSigner,,) = ECDSA.tryRecover(digest, v, r, s);
        return (actualSigner == signer);
    }

    /**
     * @dev Validates a Merkle proof for a claim.
     * @param account The address of the user claiming the airdrop.
     * @param amount The amount of tokens to be claimed.
     * @param merkleProof The Merkle proof provided by the user.
     * @return True if the proof is valid, false otherwise.
     */
    function _isValidProof(address account, uint256 amount, bytes32[] calldata merkleProof)
        internal
        view
        returns (bool)
    {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(account, amount))));
        bool isValid = MerkleProof.verify(merkleProof, i_merkleRoot, leaf);
        return isValid;
    }

    /*///////////////////////////////////////////////////////
                              GETTERS
    ///////////////////////////////////////////////////////*/

    /**
     * @notice Checks if a user has already claimed their airdrop.
     * @param user The address of the user to check.
     * @return True if the user has claimed the airdrop, false otherwise.
     */
    function getIfUserHasClaimedAirdrop(address user) external view returns (bool) {
        return s_hasClaimedAirdrop[user];
    }

    /**
     * @notice Returns the Merkle root used to validate claims.
     * @return The Merkle root.
     */
    function getMerkleRoot() external view returns (bytes32) {
        return i_merkleRoot;
    }

    /**
     * @notice Returns the EIP-712 message type hash.
     * @return The type hash for claim messages.
     */
    function getMessageTypeHash() external pure returns (bytes32) {
        return MESSAGE_TYPEHASH;
    }

    /**
     * @notice Returns the ERC20 token used for the airdrop.
     * @return The airdrop token.
     */
    function getAirdropToken() external view returns(IERC20){
        return i_airdropToken;
    }
}
