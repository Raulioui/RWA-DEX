
# RWA DEX (Testnet Demo) — Tokenized Stocks + Chainlink Functions + Alpaca (Sandbox) + On-chain Governance

> ⚠️ **Portfolio / testnet demo only — NOT production-ready.**
>
> This project demonstrates an end-to-end Web3 system that tokenizes real-world assets (stocks) on-chain using:
> - **Solidity + Foundry** smart contracts
> - **Chainlink Functions** to execute off-chain orders
> - **Alpaca Broker API (Sandbox)** as the off-chain execution venue
> - **OpenZeppelin Governor + Timelock** to govern privileged actions (listing assets, upgrades, emergency controls)
> - **Next.js + wagmi/viem** frontend to interact with the protocol and governance.


## Overview

The protocol allows users to:
1) **Register** (demo accountId mapping to simulate off-chain brokerage account)
2) **Mint** an on-chain ERC20 “AssetToken” (e.g. AAPL, TSLA) by paying an internal USD-like token
3) **Redeem** AssetTokens back to the base currency

Mint/redeem is **asynchronous**:
- the on-chain contract requests an off-chain action via **Chainlink Functions**
- the DON executes JS code that calls **Alpaca sandbox** to place the order
- the DON returns the filled amount
- the on-chain contract finalizes by minting/burning and refunding on failure

All privileged actions (asset listings, upgrades, emergency pause, etc.) are controlled by **governance**.

---

## Key features

### Smart Contracts
- **AssetPool**: protocol router + factory + registry  
  - maintains the token registry (ticker → token address)
  - user actions: register, mint, redeem
  - governance-only actions: create/remove token registry, upgrades, emergency pause, etc.
- **AssetToken**: ERC20 per asset deployed via **Beacon Proxy** pattern  
  - each asset is a proxy pointing to a shared implementation through an UpgradeableBeacon
  - requests mint/redeem via Chainlink Functions and handles timeouts/refunds
- **ChainlinkCaller**: Chainlink Functions integration layer  
  - stores the JS sources (mint/redeem)
  - authorizes tokens
  - receives fulfillments and forwards results to AssetToken
- **BrokerDollar**: internal “USD-like” demo token used as base currency
- **Governance**: OpenZeppelin Governor + Timelock  
  - **Timelock owns AssetPool**
  - proposals can list new assets by calling `AssetPool.createTokenRegistry(...)`


---

## Architecture

### High-level flow (mint)

### Mint flow

1. **User** calls `AssetPool.mintAsset()`
2. `AssetToken._mintAsset()` creates a **Chainlink Functions** request
3. The **Chainlink DON** runs JS (`mintAsset.js`) and calls the **Alpaca sandbox** API
4. The DON fulfills the request: `ChainlinkCaller` → `AssetToken.onFulfill()`
5. `AssetToken` **mints tokens** to the user, or **refunds** on failure/timeout


### Token deployment model
- Asset tokens are deployed as **BeaconProxy** instances.
- All proxies share a single implementation through `UpgradeableBeacon`.
- Upgrades can be performed for all assets at once (governance-only).

---

## Governance lifecycle

Typical proposal flow (OZ Governor + Timelock):

1. **Delegate** voting power (if using ERC20Votes):
   - `BGT.delegate(yourAddress)`
2. **Create proposal**:
   - Governor `propose(targets, values, calldatas, description)`
3. Wait until proposal becomes **Active** (after voting delay)
4. **Vote**:
   - `castVote(proposalId, support)` (For/Against/Abstain)
5. If **Succeeded**:
   - `queue(targets, values, calldatas, descriptionHash)`
6. Then **Execute**:
   - `execute(targets, values, calldatas, descriptionHash)`
