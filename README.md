# 🏦 RWA Exchange

**Asynchronous on-chain settlement for tokenized real-world assets**

<div align="center">

![Trading Interface Screenshot](./docs/screenshots/trading-interface.png)

**[Live Demo](https://your-demo.vercel.app)** • **[Video Walkthrough](https://loom.com/your-video)** • **[Technical Deep Dive](https://your-blog-post-link)**

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

<div align="center">

![Mint Flow Screenshot](./docs/screenshots/mint-flow.png)

</div>

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

<div align="center">

![Architecture Diagram](./docs/screenshots/architecture.png)

</div>

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

## Screenshots

<div align="center">

### Trading Interface
![Trading Interface](./docs/screenshots/trading.png)

### Governance Dashboard
![Governance](./docs/screenshots/governance.png)

### Portfolio View
![Portfolio](./docs/screenshots/portfolio.png)

</div>

---

## Video Demo

<div align="center">

[![Watch Demo](./docs/screenshots/video-thumbnail.png)](https://loom.com/your-video)

**3-minute walkthrough:**
- User registration + BrokerDollar minting
- Purchasing dTSLA tokens
- Request tracking (pending → fulfilled)
- Creating governance proposals
- Redeeming tokens

</div>

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

## Future Improvements

For production deployment:

- [ ] KYC/AML compliance layer
- [ ] Legal custody infrastructure
- [ ] Privacy (zk-proofs for accounts)
- [ ] Multiple oracle sources
- [ ] Cross-chain bridges
- [ ] Advanced order types
- [ ] MEV protection
- [ ] Monitoring/alerting

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

Focus is on solving the **technical problem** of async settlement, not regulatory requirements.

---

## Related Writing

📝 [Technical Deep Dive: Building Request-Based RWA Settlement](https://your-blog-link)

Topics covered:
- Sync vs. async execution mismatch
- State machine design patterns
- Slippage protection mechanisms
- Governance under async risk

---

## Contact

**Raul Muela Morey**

[![GitHub](https://img.shields.io/badge/GitHub-Raulioui-181717?logo=github)](https://github.com/Raulioui)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-Connect-0077B5?logo=linkedin)](https://linkedin.com/in/your-profile)
[![Email](https://img.shields.io/badge/Email-Contact-D14836?logo=gmail)](mailto:your.email@example.com)

Open to blockchain development opportunities and technical discussions.

---

## License

MIT License - See [LICENSE](./LICENSE) for details

---

## Acknowledgments

- **Chainlink** for oracle infrastructure
- **Alpaca** for sandbox broker API  
- **OpenZeppelin** for secure contract libraries
- **Foundry** for Solidity tooling

---

<div align="center">

**⭐ Star this repo if you found it interesting! ⭐**

Built with ❤️ to explore async settlement design in DeFi

[Report Bug](https://github.com/Raulioui/rwa-exchange/issues) • [Request Feature](https://github.com/Raulioui/rwa-exchange/issues)

</div>
