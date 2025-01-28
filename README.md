# StakeDropV1 - Staking and Airdrop Protocol

## Overview

**StakeDropV1** is a staking protocol that allows users to stake **ETH** and **StakeDropToken (SDT)** tokens with various lock-up periods. Users earn rewards based on their stake duration, with options for early unstaking (subject to penalties). The protocol includes an airdrop mechanism for distributing SDT tokens to randomly selected stakers, ensuring secure and fair distribution using standards like **ECDSA**, **Merkle Tree**, and **EIP712**.

This contract is **upgradeable**, using the **UUPS (Universal Upgradeable Proxy Standard)**.

---

## Features

1. **Staking**:
   - Users can stake ETH or SDT tokens.
   - Staking rewards vary based on lock-up durations: Quarterly, Biannual, and Annual.
   - Early unstaking is allowed but incurs penalties paid to the protocol.

2. **Rewards**:
   - Rewards are distributed proportionally to the staking duration.
   - Additional rewards for longer lock-up periods:
     - Quarterly: 3%
     - Biannual: 5%
     - Annual: 8%

3. **Airdrop**:
   - SDT tokens are distributed to randomly selected users who have staked.
   - Utilizes cryptographic standards (ECDSA, Merkle Tree, EIP712) for secure airdrops.

4. **Upgradeable**:
   - The contract uses the UUPS upgradeable proxy pattern, allowing seamless upgrades.

5. **Secure**:
   - Includes a reentrancy guard to prevent attacks.
   - Modular architecture for extensibility.

---

## Contracts and Components

### 1. **StakeDropV1**
   - Core staking contract.
   - Allows users to stake, unstake, and claim rewards.
   - Handles staking and reward distribution logic.

### 2. **StakeDropToken**
   - ERC-20 token contract representing the protocol token (**SDT**).

### 3. **StakeDropAirdrop**
   - Airdrop contract to distribute SDT tokens to random stakers.
   - Ensures secure and fair airdrops.

---

## Deployment Scripts

Deployment scripts are provided for the following:
- **StakeDropV1**: Core staking contract.
- **StakeDropAirdrop**: Airdrop mechanism.

Scripts automate the deployment process and include parameter initialization.

---

## Testing

The project includes extensive tests:
1. **Unit Tests**:
   - Test individual functionalities of **StakeDropV1** and **StakeDropAirdrop**.
   - Verify staking, unstaking, rewards, and penalties.

2. **Fuzz Testing**:
   - Short invariant tests for **StakeDropV1** to ensure consistent behavior under random inputs.

---

## Installation and Setup

### Prerequisites
- [Foundry](https://github.com/foundry-rs/foundry): Development environment for Ethereum smart contracts.

### Clone the Repository
```bash
git clone https://github.com/arefxv/stakedrop.git
cd stakedrop
```

## Usage

### Compilation


Compile the smart contracts:

```bash
forge build
```

### Running Tests

Execute the test suite:

```bash
forge test
```

### Deployment

Deploy contracts using Foundry's deploy script:

```bash
//StakeDropV1
forge script script/StakeDrop/DeployStakeDropV1.s.sol --rpc-url <YOUR_RPC_URL> --private-key <YOUR_PRIV_KEY> --broadcast 

//StakeDropAirdrop
forge script script/Airdrop/target/DeployStakeDropAirdrop.s.sol --rpc-url <YOUR_RPC_URL> --private-key <YOUR_PRIV_KEY> --broadcast 
```
Replace `<YOUR_RPC_URL>` with your Ethereum node URL (e.g., Alchemy, Infura, or Anvil).

---

## Contract Details

### StakeDropV1 Contract

* **Constructor Parameters:**
  
    * `IERC20 airdropToken`: Address of the airdrop token (SDT)
  
* **Modifiers:**
  
    * `moreThanZero`: Ensures input amount is greater than zero.
    * `hasEnoughBalance`: Ensures the contract has sufficient balance for operations.
  
* **Events:**

    * `EthStaked`: Logs ETH staking.
    * `SdtStaked`: Logs SDT staking.
    * `EthUnstaked`: Logs ETH unstaking.
    * `SdtUnstaked`: Logs SDT unstaking.
    * `EthUnstakedForce`: Logs forced ETH unstaking with penalties.
    * `SdtUnstakedForce`: Logs forced SDT unstaking with penalties.

---

## Upgradeability

The contract is upgradeable using **UUPSUpgradeable**. Upgrades are restricted to the owner of the proxy contract. Ensure only trusted entities are given ownership privileges.

---

## Security

1. Reentrancy Protection:

    * Critical functions are protected with `nonReentrant` modifiers to prevent reentrancy attacks.

2. Airdrop Security:

    * Uses cryptographic standards to ensure fair and tamper-proof distribution.

3. Access Control:

    * Only the owner can perform administrative actions like contract upgrades and fund recovery.

4. Testing:

* Thorough unit and fuzz tests validate contract behavior under various scenarios.

---

# THANKS!

---

# Author

###  [ArefXV](https://linktr.ee/arefxv)# stakedrop
