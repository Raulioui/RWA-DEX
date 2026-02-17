# 🏦 RWA Exchange

**Asynchronous on-chain settlement for tokenized real-world assets**

<div align="center">

**[Technical Deep Dive](https://medium.com/@raulmuelamorey/lessons-from-building-a-request-based-rwa-protocol-1486dff177b7)**

![Solidity](https://img.shields.io/badge/Solidity-0.8.25-blue)
![Foundry](https://img.shields.io/badge/Foundry-tested-green)
![Next.js](https://img.shields.io/badge/Next.js-14-black)
![Chainlink](https://img.shields.io/badge/Chainlink-Functions-red)
![License](https://img.shields.io/badge/license-MIT-blue)

</div>

---

## Overview

A full-stack DeFi protocol for trading tokenized stocks (dTSLA, dAAPL, etc.) with real broker execution. Users mint on-chain tokens backed by off-chain asset positions, managed through asynchronous oracle-based settlement.

**Key capabilities:**
- Mint tokenized assets backed by real broker positions (Alpaca sandbox)
- Redeem tokens through automated broker sales
- Trade on-chain with full ERC20 compatibility
- Participate in protocol governance via on-chain voting


---

## The Problem

Smart contracts execute synchronously (single block), but real-world asset execution is asynchronous (seconds/minutes).
```
❌ Naive approach: user.mint() → [30s broker API call] → mint tokens
                                        ↑
                              Transaction times out / fails

✅ This project: user.mint() → create request → [async execution] → callback → settle
```

This protocol solves the **sync/async mismatch** using a request-based state machine that decouples user intent from settlement.

---

## Features

- ✅ **Async-safe settlement** — Oracle callbacks don't block transactions
- ✅ **Refund protection** — Users never lose funds to execution failures
- ✅ **Slippage bounds** — Settlement validated against expected amounts
- ✅ **Upgradeable tokens** — Beacon Proxy pattern for atomic upgrades
- ✅ **On-chain governance** — OpenZeppelin Governor + Timelock
- ✅ **Oracle integration** — Chainlink Functions for off-chain execution
- ✅ **Real execution** — Alpaca broker API (sandbox)
- ✅ **Modern UI** — Next.js 14, wagmi v2, responsive design

---

## Quick Start

### Prerequisites
```bash
- Node.js 18+
- Foundry (https://book.getfoundry.sh/)
- Arbitrum Sepolia RPC URL
```

### Installation
```bash
# Clone repo
git clone https://github.com/Raulioui/rwa-exchange
cd rwa-exchange

# Install dependencies
npm install

# Configure environment
cp .env.example .env
# Add your keys to .env

# Run tests
forge test

# Start frontend
npm run dev
```

### Deployment
```bash
# Deploy contracts
forge script script/DeployProtocol.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC \
  --broadcast
```

---

## Architecture

### Contracts
```
AssetPool          → Protocol coordinator, asset registry, user registration
AssetToken         → ERC20 per asset, request lifecycle management
ChainlinkCaller    → Oracle integration layer
Governance         → OpenZeppelin Governor + Timelock
BrokerDollar       → Demo USDT for testing
```

### Request Flow
```
1. User calls mintAsset()
2. Funds escrowed, request created (PENDING)
3. Chainlink executes off-chain (Alpaca broker)
4. Callback received with execution result
5. Validate slippage → mint tokens or refund
```


---

## Tech Stack

**Smart Contracts**
- Solidity 0.8.25
- OpenZeppelin (ERC20, Governor, Proxy, Timelock)
- Chainlink Functions
- Foundry

**Frontend**
- Next.js 14 (App Router)
- TypeScript
- wagmi v2 / viem
- Tailwind CSS
- RainbowKit

**Off-Chain**
- Chainlink Functions (JavaScript runtime)
- Alpaca Broker API (sandbox)

---

## Testing
```bash
# Run all tests
forge test

# Verbose output
forge test -vvv

# Coverage report
forge coverage
```

**Coverage:** 95%+ across 30+ unit and integration tests

---

## Project Stats

| Metric | Value |
|--------|-------|
| Smart Contract Lines | 1,200+ |
| Frontend Lines | 5,000+ |
| Test Coverage | 95%+ |
| Tests Written | 30+ |
| Development Time | 6 weeks |
| Blockchain | Arbitrum Sepolia |

---

## Key Technical Decisions

### 1. Request-Based State Machine

Mint/redeem modeled as persistent requests with explicit lifecycle:
```
PENDING → FULFILLED / ERROR / EXPIRED
```

Prevents state corruption from async failures.

### 2. Beacon Proxy Pattern

All AssetTokens share one implementation via UpgradeableBeacon. Enables atomic upgrades of all tokens through governance.

### 3. Slippage Protection

Users specify `expectedAmount` on submission. Settlement validates actual vs. expected, refunds on excessive deviation.

### 4. Refund-First Error Handling

All failure paths (timeout, slippage, API error) trigger automatic refunds. User funds never trapped.

---

## What I Learned

**Technical Skills**
- Designing async-safe smart contract systems
- Implementing DAO governance (Governor + Timelock)
- Beacon Proxy upgradeable architecture
- Oracle security and callback validation
- Full-stack web3 development (wagmi v2, Next.js)

**Soft Skills**
- Managing complexity in multi-contract systems
- Balancing security vs. user experience
- Writing production-grade tests
- Technical documentation


---

## Project Structure
```
rwa-exchange/
├── src/
│   ├── AssetPool.sol
│   ├── AssetToken.sol
│   ├── ChainlinkCaller.sol
│   ├── BrokerDollar.sol
│   └── governance/
├── test/
│   ├── AssetPool.t.sol
│   └── AssetToken.t.sol
├── script/
│   └── DeployProtocol.s.sol
├── chainlink-functions/
│   ├── mint.js
│   └── redeem.js
└── frontend/
    ├── app/
    └── components/
```

---



## Disclaimer

⚠️ **Portfolio project for learning purposes — NOT production-ready**

Intentional simplifications:
- Alpaca sandbox (no real money)
- Demo USDT (BrokerDollar)
- Public account storage (privacy risk)
- Zero governance delay (demo only)
- No KYC/custody/compliance

**Do not use with real funds.**





## License

MIT License - See [LICENSE](./LICENSE) for details

---


