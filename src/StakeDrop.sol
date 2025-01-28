// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ReentrancyGuard} from "@openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {console} from "forge-std/console.sol";

/**
 * @title StakeDropV1
 * @author ArefXV
 * @dev This contract allows users to stake both ETH and SDT tokens. Users can stake their assets for a specific duration and receive rewards based on the length of their lock-up time.
 * @dev Users are also able to unstake their assets before the lock time ends; however, they will incur a penalty paid to the protocol for early withdrawal
 * @dev This contract includes airdrop functionality, enabling the protocol to distribute SDT tokens to random users. The airdrop logic utilizes ECDSA, Merkle Tree, and EIP712 standards for secure distribution(see the airdrop contracts at "src/StakeDropAirdrop.sol")
 * @dev The contract is upgradeable, allowing the owner to upgrade the contract via a proxy mechanism
 */
contract StakeDropV1 is ReentrancyGuard, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    /*///////////////////////////////////////////////////////
                              ERRORS
    ///////////////////////////////////////////////////////*/
    error StakeDropV1__AmountMustBeMoreThanZero();
    error StakeDropV1__TransferFailed();
    error StakeDropV1__InvalidAmount();
    error StakeDropV1__StakeTimeNotPassed();
    error StakeDropV1__OnlyOwner();
    error StakeDropV1__ContractHasNoBalance();
    error StakeDropV1__ContractHasNoEnoughBalance();
    error StakeDropV1__InsufficientAmount();
    error StakeDropV1__NotStakedYet();
    error StakeDropV1__RewardAlreadyClaimed();
    error StakeDropV1__NoRewardsToClaim();

    /*///////////////////////////////////////////////////////
                              TYPES
    ///////////////////////////////////////////////////////*/
    /**
     * @notice A struct representing user staking details
     * @param ethAmount The amount of ETH staked by the user
     * @param ethUserTimestamp The timestamp of the ETH staking lock
     * @param sdtAmount The amount of SDT tokens staked by the user
     * @param sdtUserTimestamp The timestamp of the SDT staking lock
     */
    struct Stake {
        uint256 ethAmount;
        uint256 ethUserTimestamp;
        uint256 sdtAmount;
        uint256 sdtUserTimestamp;
    }

    /*///////////////////////////////////////////////////////
                        STATE VARIABLES
    ///////////////////////////////////////////////////////*/
    /// @notice The standard lock-up time for staking, set to 1 month (in seconds)
    uint256 private constant LOCK_TIME = 2592000;

    /// @notice The penalty fee (percentage) for early withdrawals
    uint256 private constant PENALTY_FEE = 5;

    /// @notice Extended lock-up time options with increased rewards
    uint256 private constant QUARTERLY_LOCK = 7776000; //3 months
    uint256 private constant BIANNUAL_LOCK = 15552000; //6 months
    uint256 private constant ANNUAL_LOCK = 31104000; //1 year

    ///@dev variables for calculating the reward
    uint256 private constant REWARD_PERCENT = 1;
    uint256 private constant QUARTERLY_REWARD_PERCENT = 3;
    uint256 private constant BIANNUAL_REWARD_PERCENT = 5;
    uint256 private constant ANNUAL_REWARD_PERCENT = 8;
    uint256 private constant REWARD_PERCENT_PRECISION = 100;

    /// @notice Mapping to track user stakes and times for both ETH and SDT tokens
    mapping(address => Stake) private s_userStakes;

    /// @notice Flags to track whether a user is currently an ETH or SDT staker
    mapping(address => bool) private s_isEthStaker;
    mapping(address => bool) private s_isSdtStaker;

    /// @notice Tracks whether a user has claimed rewards for specific stakes
    mapping(address => mapping(uint256 => bool)) private s_hasClaimedEthReward;
    mapping(address => mapping(uint256 => bool)) private s_hasClaimedSdtReward;

    /// @notice The ERC20 token used for airdrops and SDT staking operations
    IERC20 private immutable i_airdropToken;

    /*///////////////////////////////////////////////////////
                              EVENTS
    ///////////////////////////////////////////////////////*/
    event EthStaked(address indexed user, uint256 indexed amount);
    event SdtStaked(address indexed user, uint256 indexed amount);
    event EthUnstaked(address indexed user, uint256 indexed amount);
    event SdtUnstaked(address indexed user, uint256 indexed amount);
    event EthUnstakedForce(address indexed user, uint256 indexed amount, uint256 penaltyAmount);
    event SdtUnstakedForce(address indexed user, uint256 indexed amount, uint256 penaltyAmount);

    /*///////////////////////////////////////////////////////
                              MODIFIERS
    ///////////////////////////////////////////////////////*/
    /**
     * @notice Ensures the provided amount is greater than zero.
     * @param amount The amount to validate.
     */
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert StakeDropV1__AmountMustBeMoreThanZero();
        }
        _;
    }

    /**
     * @notice Ensures the contract has sufficient balance for a requested operation.
     * @param value The required balance.
     */
    modifier hasEnoughBalance(uint256 value) {
        if (address(this).balance < value) {
            revert StakeDropV1__ContractHasNoEnoughBalance();
        }
        _;
    }
    /*///////////////////////////////////////////////////////
                              FUNCTIONS
    ///////////////////////////////////////////////////////*/

    /**
     * @notice Constructor to set the SDT airdrop token address.
     * @param airdropToken The ERC20 token used for airdrops and SDT staking.
     */
    constructor(IERC20 airdropToken) {
        i_airdropToken = airdropToken;
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract, setting the deployer as the owner and enabling UUPS upgrades
     *      This function can only be called once, ensuring secure initialization
     */
    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    /*///////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////*/
    /**
     * @notice Allows a user to stake ETH in the contract
     * @dev Uses a non-reentrant modifier to prevent reentrancy attacks
     * @dev Ensures the staked amount is greater than zero
     * @dev Calls the internal `_stake` function to handle the staking logic
     */
    function stakeEth() external payable nonReentrant moreThanZero(msg.value) {
        _stake(msg.sender, msg.value, true);
    }

    /**
     * @notice Allows a user to stake SDT (an ERC20 token) in the contract
     * @dev Uses a non-reentrant modifier to prevent reentrancy attacks
     * @dev Ensures the staked amount is greater than zero
     * @dev Calls the internal `_stake` function to handle the staking logic
     * @param amount The amount of SDT to be staked
     */
    function stakeSdt(uint256 amount) external nonReentrant moreThanZero(amount) {
        _stake(msg.sender, amount, false);
    }

    /**
     * @notice Allows a user to unstake their ETH or SDT from the contract
     * @dev Uses a non-reentrant modifier to prevent reentrancy attacks
     * @dev Ensures the unstaked amount is greater than zero
     * @dev Validates that the user has staked and the lock time has passed
     * @param amount The amount to be unstaked
     * @param isEth A boolean indicating whether to unstake ETH (`true`) or SDT (`false`)
     */
    function unstake(uint256 amount, bool isEth) external nonReentrant moreThanZero(amount) {
        if (isEth) {
            _unstake(msg.sender, amount, true);
        } else {
            _unstake(msg.sender, amount, false);
        }
    }

    /**
     * @notice Allows a user to force-unstake their ETH or SDT from the contract, incurring a penalty
     * @dev Uses a non-reentrant modifier to prevent reentrancy attacks
     * @dev Ensures the force-unstaked amount is greater than zero
     * @dev Applies a penalty before returning the remaining amount to the user
     * @param amount The amount to be force-unstaked
     * @param isEth A boolean indicating whether to force-unstake ETH (`true`) or SDT (`false`)
     */
    function forceUnstake(uint256 amount, bool isEth) external nonReentrant moreThanZero(amount) {
        if (isEth) {
            _forceUnstake(msg.sender, amount, true);
        } else {
            _forceUnstake(msg.sender, amount, false);
        }
    }

    /**
     * @notice Claims all rewards for a user based on their staking type (ETH or SDT)
     * @dev This function distributes all rewards (quarterly, biannual, and annual) for the user
     * @param user The address of the user claiming rewards
     * @param isEth A boolean indicating whether the rewards are for ETH (`true`) or SDT (`false`)
     */
    function claimReward(address user, bool isEth) external nonReentrant {
        if (isEth) {
            _reward(user, true);
            _quarterlyReward(user, true);
            _biannualReward(user, true);
            _annualReward(user, true);
        } else {
            _reward(user, false);
            _quarterlyReward(user, false);
            _biannualReward(user, false);
            _annualReward(user, false);
        }
    }

    /**
     * @notice Allows the contract owner to recover SDT tokens held by the contract
     * @dev Ensures the contract has enough balance to recover the specified amount
     * @dev Transfers the tokens to the owner
     * @param amount The amount of SDT to be recovered
     */
    function recoverSdt(uint256 amount) external onlyOwner hasEnoughBalance(amount) {
        i_airdropToken.safeTransfer(owner(), amount);
    }

    /**
     * @notice Allows the contract owner to recover ETH held by the contract
     * @dev Ensures the contract has enough balance to recover the specified amount
     * @dev Transfers the ETH to the owner
     * @param amount The amount of ETH to be recovered
     */
    function recoverEth(uint256 amount) external onlyOwner hasEnoughBalance(amount) {
        (bool success,) = owner().call{value: amount}("");
        if (!success) {
            revert StakeDropV1__TransferFailed();
        }
    }

    /*///////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////*/

    /**
     * @notice Internal function to handle staking logic for ETH and SDT
     * @dev Updates the user's staking details and emits an event
     * @param user The address of the user staking the asset
     * @param amount The amount to be staked
     * @param isEth A boolean indicating whether the asset is ETH (`true`) or SDT (`false`)
     */
    function _stake(address user, uint256 amount, bool isEth) internal {
        Stake storage stake = s_userStakes[user];
        uint256 unlockTime = LOCK_TIME;

        if (isEth) {
            if (stake.ethAmount == 0) {
                s_isEthStaker[user] = true;
            }

            stake.ethAmount += amount;
            stake.ethUserTimestamp = unlockTime;
            s_hasClaimedEthReward[user][amount] = false;

            emit EthStaked(user, amount);
        } else {
            if (stake.sdtAmount == 0) {
                s_isSdtStaker[user] = true;
            }

            stake.sdtAmount += amount;
            stake.sdtUserTimestamp = unlockTime;

            i_airdropToken.safeTransferFrom(user, address(this), amount);
            s_hasClaimedSdtReward[user][amount] = false;

            emit SdtStaked(user, amount);
        }
    }

    /**
     * @notice Internal function to handle unstaking logic for ETH and SDT
     * @dev Validates staking conditions and updates user details
     * @param user The address of the user unstaking the asset
     * @param amount The amount to be unstaked
     * @param isEth A boolean indicating whether the asset is ETH (`true`) or SDT (`false`)
     * @custom:throws StakeDropV1__NotStakedYet if user tries to unstake but didn't stake
     * @custom:throws StakeDropV1__InvalidAmount if user's staked amount be lower than amount inserted
     * @custom:throws StakeDropV1__StakeTimeNotPassed if the unlock time hasn't come yet
     */
    function _unstake(address user, uint256 amount, bool isEth) internal {
        Stake storage stake = s_userStakes[user];
        uint256 ethUserStakedTime = stake.ethUserTimestamp;
        uint256 sdtUserStakedTime = stake.sdtUserTimestamp;

        if (isEth) {
            if (!s_isEthStaker[msg.sender]) {
                revert StakeDropV1__NotStakedYet();
            }

            if (amount > stake.ethAmount) {
                revert StakeDropV1__InvalidAmount();
            }

            if (block.timestamp < ethUserStakedTime) {
                revert StakeDropV1__StakeTimeNotPassed();
            }

            if (stake.ethAmount > amount) {
                stake.ethAmount -= amount;
            } else {
                delete stake.ethAmount;
                delete stake.ethUserTimestamp;
                delete s_isEthStaker[user];
            }

            payable(user).transfer(amount);

            emit EthUnstaked(user, amount);
        } else {
            if (!s_isSdtStaker[user]) {
                revert StakeDropV1__NotStakedYet();
            }

            if (amount > stake.sdtAmount) {
                revert StakeDropV1__InvalidAmount();
            }

            if (block.timestamp < sdtUserStakedTime) {
                revert StakeDropV1__StakeTimeNotPassed();
            }

            if (stake.sdtAmount > amount) {
                stake.sdtAmount -= amount;
            } else {
                delete stake.sdtAmount;
                delete stake.sdtUserTimestamp;
                delete s_isSdtStaker[user];
            }

            i_airdropToken.safeTransfer(user, amount);

            emit SdtUnstaked(user, amount);
        }
    }

    /**
     * @notice Forcefully unstake a specific amount for a user and apply a penalty
     * @dev This function updates the staking records and deducts a penalty from the amount
     * @param user The address of the user whose funds are being forcefully unstaked
     * @param amount The amount to be unstaked
     * @param isEth A boolean indicating whether the unstaking is for ETH (`true`) or SDT (`false`)
     * @custom:throws StakeDropV1__NotStakedYet if user tries to unstake but didn't stake
     * @custom:throws StakeDropV1__InvalidAmount if user's staked amount be lower than amount inserted
     */
    function _forceUnstake(address user, uint256 amount, bool isEth) internal {
        Stake storage stake = s_userStakes[user];
        uint256 penalty = _penalty(amount);
        uint256 finalAmount = amount - penalty;

        if (isEth) {
            if (!s_isEthStaker[user]) {
                revert StakeDropV1__NotStakedYet();
            }

            if (stake.ethAmount < amount) {
                revert StakeDropV1__InvalidAmount();
            } else if (stake.ethAmount > amount) {
                stake.ethAmount -= amount;
            } else {
                delete stake.ethAmount;
                delete stake.ethUserTimestamp;
                delete s_isEthStaker[user];
            }

            emit EthUnstakedForce(user, amount, penalty);
            (bool success,) = user.call{value: finalAmount}("");
            if (!success) {
                revert StakeDropV1__TransferFailed();
            }
        } else {
            if (!s_isSdtStaker[msg.sender]) {
                revert StakeDropV1__NotStakedYet();
            }

            if (stake.sdtAmount < amount) {
                revert StakeDropV1__InvalidAmount();
            } else if (stake.sdtAmount > amount) {
                stake.sdtAmount -= amount;
            } else {
                delete stake.sdtAmount;
                delete stake.sdtUserTimestamp;
                delete s_isSdtStaker[user];

                emit SdtUnstakedForce(user, amount, penalty);
                i_airdropToken.safeTransfer(user, finalAmount);
            }
        }
    }

    /**
     * @notice Internal function to calculate and distribute staking rewards.
     * @dev Rewards are distributed based on the staking duration and type.
     * @param account The address of the staker.
     * @param isEth A boolean indicating whether to calculate rewards for ETH (`true`) or SDT (`false`).
     * @custom:throws StakeDropV1__StakeTimeNotPassed if the unlock time hasn't come yet
     * @custom:throws StakeDropV1__NoRewardsToClaim if claimed befor on not eligible
     * @custom:throws StakeDropV1__NotStakedYet if user tries to unstake but didn't stake
     */
    function _reward(address account, bool isEth) internal {
        Stake storage stake = s_userStakes[account];

        uint256 quarterlyStakeEth = stake.ethUserTimestamp + QUARTERLY_LOCK;
        uint256 quarterlyStakeSdt = stake.sdtUserTimestamp + QUARTERLY_LOCK;

        if (isEth) {
            if (s_isEthStaker[account]) {
                if (block.timestamp < stake.ethUserTimestamp) {
                    revert StakeDropV1__StakeTimeNotPassed();
                }

                uint256 reward = (stake.ethAmount * REWARD_PERCENT) / REWARD_PERCENT_PRECISION;

                if (s_hasClaimedEthReward[account][reward]) {
                    revert StakeDropV1__NoRewardsToClaim();
                }

                if (block.timestamp >= stake.ethUserTimestamp && block.timestamp < quarterlyStakeEth) {
                    s_hasClaimedEthReward[account][reward] = true;
                    payable(account).transfer(reward);
                }
            } else {
                revert StakeDropV1__NotStakedYet();
            }
        } else {
            if (s_isSdtStaker[account]) {
                if (block.timestamp < stake.sdtUserTimestamp) {
                    revert StakeDropV1__StakeTimeNotPassed();
                }

                if (stake.sdtAmount == 0) {
                    revert StakeDropV1__NotStakedYet();
                }

                if (!s_isSdtStaker[account]) {
                    revert StakeDropV1__NotStakedYet();
                }
                uint256 reward = (stake.sdtAmount * REWARD_PERCENT) / REWARD_PERCENT_PRECISION;
                if (s_hasClaimedSdtReward[account][reward]) {
                    revert StakeDropV1__NoRewardsToClaim();
                }

                if (block.timestamp >= stake.sdtUserTimestamp && block.timestamp < quarterlyStakeSdt) {
                    i_airdropToken.safeTransfer(account, reward);
                    s_hasClaimedSdtReward[account][reward] = true;
                }
            } else {
                revert StakeDropV1__NotStakedYet();
            }
        }
    }

    /**
     * @notice Internal function to calculate and distribute the quarterly staking reward
     * @dev Rewards are distributed if the staking duration is within the quarterly time frame
     * @param account The address of the staker
     * @param isEth A boolean indicating whether the rewards are for ETH (`true`) or SDT (`false`)
     * @custom:throws StakeDropV1__StakeTimeNotPassed if the unlock time hasn't come yet
     * @custom:throws StakeDropV1__NoRewardsToClaim if claimed befor on not eligible
     * @custom:throws StakeDropV1__NotStakedYet if user tries to unstake but didn't stake
     */
    function _quarterlyReward(address account, bool isEth) internal {
        // Fetch the stake details for the given user
        Stake storage stake = s_userStakes[account];

        // Calculate the reward eligibility times for ETH and SDT staking
        uint256 quarterlyStakeEth = stake.ethUserTimestamp + QUARTERLY_LOCK;
        uint256 biannualStakeEth = stake.ethUserTimestamp + BIANNUAL_LOCK;
        uint256 quarterlyStakeSdt = stake.sdtUserTimestamp + QUARTERLY_LOCK;
        uint256 biannualStakeSdt = stake.sdtUserTimestamp + BIANNUAL_LOCK;

        if (isEth) {
            // Check if the user is an ETH staker
            if (s_isEthStaker[account]) {
                // Ensure the stake duration has passed
                if (block.timestamp < stake.ethUserTimestamp) {
                    revert StakeDropV1__StakeTimeNotPassed();
                }

                // Ensure the user has actually staked ETH
                if (stake.ethAmount == 0) {
                    revert StakeDropV1__NotStakedYet();
                }

                // Double-check that the user is an ETH staker
                if (!s_isEthStaker[account]) {
                    revert StakeDropV1__NotStakedYet();
                }

                // Calculate the ETH reward based on the quarterly reward percentage
                uint256 reward = (stake.ethAmount * QUARTERLY_REWARD_PERCENT) / REWARD_PERCENT_PRECISION;

                // Ensure the user hasn't already claimed this reward
                if (s_hasClaimedEthReward[account][reward]) {
                    revert StakeDropV1__NoRewardsToClaim();
                }

                // Check if the current time is within the quarterly reward window
                if (block.timestamp >= quarterlyStakeEth && block.timestamp < biannualStakeEth) {
                    console.log("Q", quarterlyStakeEth);
                    console.log("B", biannualStakeEth);

                    // Transfer the calculated reward to the user
                    payable(account).transfer(reward);

                    // Mark the reward as claimed to prevent double-claiming
                    s_hasClaimedEthReward[account][reward] = true;
                }
            } else {
                // Revert if the user is not an ETH staker
                revert StakeDropV1__NotStakedYet();
            }
        } else {
            if (s_isSdtStaker[account]) {
                if (block.timestamp < stake.sdtUserTimestamp) {
                    revert StakeDropV1__StakeTimeNotPassed();
                }

                if (stake.sdtAmount == 0) {
                    revert StakeDropV1__NotStakedYet();
                }

                if (!s_isSdtStaker[account]) {
                    revert StakeDropV1__NotStakedYet();
                }

                uint256 reward = (stake.sdtAmount * QUARTERLY_REWARD_PERCENT) / REWARD_PERCENT_PRECISION;
                if (s_hasClaimedSdtReward[account][reward]) {
                    revert StakeDropV1__NoRewardsToClaim();
                }

                if (block.timestamp >= quarterlyStakeSdt && block.timestamp < biannualStakeSdt) {
                    i_airdropToken.safeTransfer(account, reward);
                    s_hasClaimedSdtReward[account][reward] = true;
                }
            } else {
                revert StakeDropV1__NotStakedYet();
            }
        }
    }

    /**
     * @notice Internal function to calculate and distribute the biannual staking reward
     * @dev Rewards are distributed if the staking duration is within the biannual time frame
     * @param account The address of the staker
     * @param isEth A boolean indicating whether the rewards are for ETH (`true`) or SDT (`false`)
     * @custom:throws StakeDropV1__StakeTimeNotPassed if the unlock time hasn't come yet
     * @custom:throws StakeDropV1__NoRewardsToClaim if claimed befor on not eligible
     * @custom:throws StakeDropV1__NotStakedYet if user tries to unstake but didn't stake
     */
    function _biannualReward(address account, bool isEth) internal {
        Stake storage stake = s_userStakes[account];

        uint256 biannualStakeEth = stake.ethUserTimestamp + BIANNUAL_LOCK;
        uint256 annualStakeEth = stake.ethUserTimestamp + ANNUAL_LOCK;
        uint256 biannualStakeSdt = stake.sdtUserTimestamp + BIANNUAL_LOCK;
        uint256 annualStakeSdt = stake.sdtUserTimestamp + ANNUAL_LOCK;

        if (isEth) {
            if (s_isEthStaker[account]) {
                if (block.timestamp < stake.ethUserTimestamp) {
                    revert StakeDropV1__StakeTimeNotPassed();
                }

                if (stake.ethAmount == 0) {
                    revert StakeDropV1__NotStakedYet();
                }

                if (!s_isEthStaker[account]) {
                    revert StakeDropV1__NotStakedYet();
                }

                uint256 reward = (stake.ethAmount * BIANNUAL_REWARD_PERCENT) / REWARD_PERCENT_PRECISION;
                if (s_hasClaimedEthReward[account][reward]) {
                    revert StakeDropV1__NoRewardsToClaim();
                }

                if (block.timestamp >= biannualStakeEth && block.timestamp < annualStakeEth) {
                    payable(account).transfer(reward);
                    s_hasClaimedEthReward[account][reward] = true;
                }
            } else {
                revert StakeDropV1__NotStakedYet();
            }
        } else {
            if (s_isSdtStaker[account]) {
                if (block.timestamp < stake.sdtUserTimestamp) {
                    revert StakeDropV1__StakeTimeNotPassed();
                }

                if (stake.sdtAmount == 0) {
                    revert StakeDropV1__NotStakedYet();
                }

                if (!s_isSdtStaker[account]) {
                    revert StakeDropV1__NotStakedYet();
                }
                uint256 reward = (stake.sdtAmount * BIANNUAL_REWARD_PERCENT) / REWARD_PERCENT_PRECISION;
                if (s_hasClaimedSdtReward[account][reward]) {
                    revert StakeDropV1__NoRewardsToClaim();
                }

                if (block.timestamp >= biannualStakeSdt && block.timestamp < annualStakeSdt) {
                    i_airdropToken.safeTransfer(account, reward);

                    s_hasClaimedSdtReward[account][reward] = true;
                }
            } else {
                revert StakeDropV1__NotStakedYet();
            }
        }
    }

    /**
     * @notice Internal function to calculate and distribute the annual staking reward
     * @dev Rewards are distributed if the staking duration is within the annual time frame
     * @param account The address of the staker
     * @param isEth A boolean indicating whether the rewards are for ETH (`true`) or SDT (`false`)
     * @custom:throws StakeDropV1__StakeTimeNotPassed if the unlock time hasn't come yet
     * @custom:throws StakeDropV1__NoRewardsToClaim if claimed befor on not eligible
     * @custom:throws StakeDropV1__NotStakedYet if user tries to unstake but didn't stake
     */
    function _annualReward(address account, bool isEth) internal {
        Stake storage stake = s_userStakes[account];

        uint256 annualStakeEth = stake.ethUserTimestamp + ANNUAL_LOCK;
        uint256 annualStakeSdt = stake.sdtUserTimestamp + ANNUAL_LOCK;

        if (isEth) {
            if (s_isEthStaker[account]) {
                if (block.timestamp < stake.ethUserTimestamp) {
                    revert StakeDropV1__StakeTimeNotPassed();
                }

                if (stake.ethAmount == 0) {
                    revert StakeDropV1__NotStakedYet();
                }

                if (!s_isEthStaker[account]) {
                    revert StakeDropV1__NotStakedYet();
                }

                uint256 reward = (stake.ethAmount * ANNUAL_REWARD_PERCENT) / REWARD_PERCENT_PRECISION;
                if (s_hasClaimedEthReward[account][reward]) {
                    revert StakeDropV1__NoRewardsToClaim();
                }

                if (block.timestamp >= annualStakeEth) {
                    payable(account).transfer(reward);
                    s_hasClaimedEthReward[account][reward] = true;
                }
            } else {
                revert StakeDropV1__NotStakedYet();
            }
        } else {
            if (s_isSdtStaker[account]) {
                if (block.timestamp < stake.sdtUserTimestamp) {
                    revert StakeDropV1__StakeTimeNotPassed();
                }

                if (stake.sdtAmount == 0) {
                    revert StakeDropV1__NotStakedYet();
                }

                if (!s_isSdtStaker[account]) {
                    revert StakeDropV1__NotStakedYet();
                }
                uint256 reward = (stake.sdtAmount * ANNUAL_REWARD_PERCENT) / REWARD_PERCENT_PRECISION;
                if (s_hasClaimedSdtReward[account][reward]) {
                    revert StakeDropV1__NoRewardsToClaim();
                }

                if (block.timestamp >= annualStakeSdt) {
                    i_airdropToken.safeTransfer(account, reward);

                    s_hasClaimedSdtReward[account][reward] = true;
                }
            } else {
                revert StakeDropV1__NotStakedYet();
            }
        }
    }

    /**
     * @notice Calculate the penalty for force unstaking a specific amount
     * @dev A fixed percentage penalty is applied to the unstaked amount
     * @param amount The amount to be unstaked
     * @return The penalty amount
     */
    function _penalty(uint256 amount) internal pure returns (uint256) {
        uint256 penaltyFee = 5;
        uint256 feePrecision = 100;
        uint256 forceUnstakePenalty = (amount * penaltyFee) / feePrecision;
        return forceUnstakePenalty;
    }

    /**
     * @notice Authorizes upgrades to a new implementation contract
     * @dev This function is protected by the `onlyOwner` modifier
     * @param newImplementation The address of the new implementation contract
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /*///////////////////////////////////////////////////////
                        GETTER FUNCTIONS
    ///////////////////////////////////////////////////////*/
    /**
     * @notice Retrieves the staking details of a user
     * @param user The address of the user whose staking details are being queried
     * @return A `Stake` struct containing the user's staking information
     */
    function getUserStakes(address user) public view returns (Stake memory) {
        return s_userStakes[user];
    }

    /**
     * @notice Checks if a user has staked ETH
     * @param user The address of the user
     * @return A boolean indicating whether the user has staked ETH
     */
    function getIfUserStakedEth(address user) external view returns (bool) {
        return s_isEthStaker[user];
    }

    /**
     * @notice Checks if a user has staked SDT
     * @param user The address of the user
     * @return A boolean indicating whether the user has staked SDT
     */
    function getIfUserStakedSdt(address user) external view returns (bool) {
        return s_isSdtStaker[user];
    }

    /**
     * @notice Checks if a user has claimed ETH rewards for a specific amount
     * @param user The address of the user
     * @param amount The reward amount being queried
     * @return A boolean indicating whether the user has claimed the ETH reward for the specified amount
     */
    function getIfUsersClaimedEthRewards(address user, uint256 amount) external view returns (bool) {
        return s_hasClaimedEthReward[user][amount];
    }

    /**
     * @notice Checks if a user has claimed SDT rewards for a specific amount
     * @param user The address of the user
     * @param amount The reward amount being queried
     * @return A boolean indicating whether the user has claimed the SDT reward for the specified amount
     */
    function getIfUsersClaimedSdtRewards(address user, uint256 amount) external view returns (bool) {
        return s_hasClaimedSdtReward[user][amount];
    }

    /**
     * @notice Retrieves the general lock time for staking
     * @return The lock time in seconds
     */
    function getLockTime() external pure returns (uint256) {
        return LOCK_TIME;
    }

    /**
     * @notice Calculates the penalty for unstaking a specific amount
     * @param amount The amount being unstaked
     * @return The penalty amount
     */
    function getPenaltyAmount(uint256 amount) external pure returns (uint256) {
        return _penalty(amount);
    }

    /**
     * @notice Retrieves the penalty fee percentage
     * @return The penalty fee percentage
     */
    function getpenaltyFee() external pure returns (uint256) {
        return PENALTY_FEE;
    }

    /**
     * @notice Retrieves the lock duration for quarterly rewards
     * @return The duration of the quarterly lock in seconds
     */
    function getQuarterlyLockDuration() external pure returns (uint256) {
        return QUARTERLY_LOCK;
    }

    /**
     * @notice Retrieves the lock duration for biannual rewards
     * @return The duration of the biannual lock in seconds
     */
    function getBiannualLockDuration() external pure returns (uint256) {
        return BIANNUAL_LOCK;
    }

    /**
     * @notice Retrieves the lock duration for annual rewards
     * @return The duration of the annual lock in seconds
     */
    function getAnnualLockDuration() external pure returns (uint256) {
        return ANNUAL_LOCK;
    }

    /**
     * @notice Retrieves the percentage of normal rewards for staking
     * @return The normal reward percentage
     */
    function getNormalRewardPercent() external pure returns (uint256) {
        return REWARD_PERCENT;
    }

    /**
     * @notice Retrieves the percentage of quarterly rewards for staking
     * @return The quarterly reward percentage
     */
    function getQuarterlyRewardPercent() external pure returns (uint256) {
        return QUARTERLY_REWARD_PERCENT;
    }

    /**
     * @notice Retrieves the percentage of biannual rewards for staking
     * @return The biannual reward percentage
     */
    function getBiannualRewardPercent() external pure returns (uint256) {
        return BIANNUAL_REWARD_PERCENT;
    }

    /**
     * @notice Retrieves the percentage of annual rewards for staking
     * @return The annual reward percentage
     */
    function getAnnualRewardPercent() external pure returns (uint256) {
        return ANNUAL_REWARD_PERCENT;
    }

    /**
     * @notice Retrieves the precision used for reward percentages
     * @return The precision value for reward percentages
     */
    function getRewardPercentPrecision() external pure returns (uint256) {
        return REWARD_PERCENT_PRECISION;
    }

    /**
     * @notice Retrieves the current Ether balance of the contract
     * @return The balance of the contract in wei
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
