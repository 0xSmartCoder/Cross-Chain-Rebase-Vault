# CrossChain Rebase Vault

A DeFi system combining a rebasing ERC20 token with a vault-based ETH deposit mechanism. The protocol integrates Chainlink CCIP for cross-chain deployment and state synchronization across Ethereum Sepolia and ZKsync.

---

## Overview

CrossChain Rebase Vault consists of two tightly coupled smart contracts:

- A **RebaseToken** with dynamic balance calculation based on time-weighted interest accrual
- A **Vault contract** that accepts ETH deposits and mints equivalent rebasing tokens

The system ensures that user balances continuously reflect accrued interest while maintaining a secure mint/burn mechanism controlled by the vault.

---

## Key Features

- Rebasing ERC20 token with time-based interest accrual
- Vault-based ETH deposit → token minting system
- Controlled mint and burn via AccessControl role
- Real-time balance calculation using dynamic interest model
- Cross-chain deployment support via Chainlink CCIP

---

## Architecture

### Rebase Token (RBT)

The RebaseToken is an ERC20 token with a dynamic balance model:

- Users do not hold static balances
- Balance increases over time based on a linear interest rate
- Interest is calculated using:


### Core Mechanics

- `balanceOf()` returns principal + accrued interest
- `_mintAccruedInterest()` settles pending interest before any state change
- `mint()` and `burn()` are restricted via `MINT_AND_BURN_ROLE`
- Interest rate is controlled by the owner and can only decrease

---

### Vault Contract

The Vault acts as the entry point for users:

#### Deposit Flow

- User sends ETH to the vault
- Vault reads current interest rate from RebaseToken
- Vault mints equivalent RBT tokens to the user
- Emits `Deposit` event

#### Redeem Flow

- User calls `redeem(amount)`
- Vault checks user’s dynamic balance
- Burns RBT tokens via RebaseToken
- Sends ETH back to user (up to vault liquidity)
- Emits `Redeem` event

---

## System Workflow

1. User deposits ETH into Vault
2. Vault mints RebaseTokens equivalent to deposit value
3. User balance increases over time via interest accrual
4. User redeems tokens at any time
5. Vault burns tokens and returns ETH

---

## Supported Networks

- Ethereum Sepolia (Primary deployment)
- ZKsync Testnet (Cross-chain deployment via CCIP)

---

## Technology Stack

- Solidity ^0.8.28
- OpenZeppelin Contracts (ERC20, AccessControl, Ownable)
- Foundry (Forge, Cast, Anvil)
- Chainlink CCIP (cross-chain messaging layer)

---

## Installation

```bash
git clone https://github.com/0xSmartCoder/Crosschain-Rebase-Vault
cd Crosschain-Rebase-Vault
forge install
forge build

```md
## Quick Start

```bash
# Give execute permission
chmod +x bridgeTozkSync.sh

# Run deployment + bridge flow
./bridgeTozkSync.sh
