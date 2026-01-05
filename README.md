
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

> Note: voting power is snapshotted at `proposalSnapshot`.  
> If you delegate *after* snapshot, your vote weight will be 0.

---

## Repositories

This project is split into two repos:

- **Contracts**: `RWA-DEX-main`  
  Solidity + Foundry + Chainlink Functions scripts and deploy scripts.
- **Frontend**: `RWA-FRONTEND-main`  
  Next.js UI + API routes for Alpaca proxy + governance pages.

---

## Quickstart

### 1) Contracts
- Deploy protocol on testnet (Foundry script)
- Save deployed addresses (AssetPool, Governor, Timelock, etc.)

### 2) Frontend
- Put addresses into `lib/contracts.js`
- Configure `.env.local` for Alpaca keys (server-only routes)
- Run `npm run dev`

---

## Deploy (Contracts)

### Requirements
- Foundry (`forge`, `cast`)
- Node.js (for Chainlink Functions scripts)
- Funded deployer wallet + RPC URL
- Chainlink Functions subscription on your target testnet

### Install
```bash
forge install
npm install



IMPLEMENTS ADDED TO TEST:
-SLIPPAGE
