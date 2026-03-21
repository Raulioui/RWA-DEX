# 🏦 RWA DEX (Testnet Demo)
**Asynchronous on-chain settlement for tokenized real-world assets**  
Solidity · Foundry · Chainlink Functions · Alpaca (Sandbox) · OZ Governor/Timelock · BeaconProxy

> ⚠️ **Portfolio / testnet demo only — NOT production-ready.**  
> This repository focuses on the **core protocol + async settlement design**.

---

## TL;DR
Smart contracts are synchronous (single-block execution). Real-world broker execution is asynchronous (seconds/minutes).  
This project solves the mismatch with a **request-based state machine**:

✅ `mint/redeem` create a request on-chain → off-chain execution via Chainlink Functions → callback settles  
✅ Funds are **escrowed** and **refunded on failure** (refund-first handling)  
✅ Tokens are **upgradeable via BeaconProxy**, controlled by **governance** (Governor + Timelock)


## Key capabilities
- Mint tokenized assets backed by broker execution (Alpaca sandbox)
- Redeem tokens through automated broker sales
- Trade on-chain with full ERC20 compatibility (per-asset ERC20)
- Govern privileged actions: listings, upgrades, emergency controls (OZ Governor + Timelock)

---

## The problem (sync vs async)
❌ Naive approach (doesn’t work):
`user.mint()` → wait 30s broker API call → mint tokens  
Transactions time out or fail. State becomes fragile.

✅ This protocol:
`user.mint()` → **create request (PENDING)** → async execution → callback → **settle** (FULFILLED / ERROR / EXPIRED)

---

## Architecture

### Contracts
- **AssetPool** — protocol coordinator + registry + user entrypoint  
  - user actions: register, mint, redeem  
  - governance-only actions: list assets / upgrades / emergency pause, etc.
- **AssetToken** — ERC20 per asset (deployed via **BeaconProxy**)  
  - manages request lifecycle for mint/redeem and settlement (mint/burn/refund)
- **ChainlinkCaller** — Chainlink Functions integration layer  
  - submits requests, receives fulfillments, forwards results to the right AssetToken
- **BrokerDollar** — internal demo “USD-like” base token
- **Governance** — OpenZeppelin Governor + Timelock  
  - Timelock is the owner of privileged protocol actions

### Request lifecycle (state machine)
`PENDING → FULFILLED | ERROR | EXPIRED`

- **PENDING**: request created, funds escrowed
- **FULFILLED**: callback validated + slippage checked → mint/burn finalization
- **ERROR**: failure path → refund
- **EXPIRED**: timeout path → refund

### Mint flow (sequence)
1. User calls `AssetPool.mintAsset(...)`
2. Protocol escrows funds + creates request in `AssetToken`
3. `ChainlinkCaller` submits Chainlink Functions request (JS in `/functions`)
4. DON executes JS → calls Alpaca sandbox → returns filled amount/result
5. `ChainlinkCaller` receives fulfillment → `AssetToken` settles:
   - validate requestId + caller + params
   - enforce slippage bounds
   - mint to user OR refund on failure

---

## Key technical decisions

### 1) Request-based state machine
Mint/redeem modeled as persistent requests with explicit lifecycle.
Prevents state corruption from async failures and enables clean refunds/timeouts.

### 2) Refund-first error handling
All failure paths (API error, bad fill, timeout, unexpected callback) trigger refunds.
Goal: user funds are **never trapped**.

### 3) Slippage protection
User submits `expectedAmount` (or bounds).
Settlement validates actual vs expected; refunds on excessive deviation.

### 4) Beacon Proxy pattern
All AssetTokens are BeaconProxy instances pointing to a shared implementation via `UpgradeableBeacon`.
Governance can upgrade all asset tokens atomically.

---

## Security notes (portfolio-level)
This is a demo, but the design includes key safety constraints:
- Callback validation: only authorized fulfillment path should settle
- Request binding: fulfillment must match `requestId` + expected request state
- Replay protection: a request can be settled once
- Escrow accounting: balances must reconcile on every settlement outcome
- Slippage checks before mint/burn finalization
- Timeouts → deterministic refund path
- Governance separation: Timelock owns privileged functions

---


### Install
```bash
git clone https://github.com/Raulioui/rwa-exchange
cd rwa-exchange
npm install