# RWA Exchange — Testnet Demo

Decentralized exchange for tokenized real-world assets on Arbitrum Sepolia.

The core design problem: smart contracts execute synchronously in a single block,
but real-world broker execution is asynchronous (seconds to minutes). This protocol
solves the mismatch with a **request-based state machine** — mint and redeem
operations create a persistent on-chain request, Chainlink Functions executes the
broker call off-chain, and the callback settles the request with full slippage
validation and refund-first error handling.

> Portfolio/testnet demo. Not production-ready.

---

## Architecture
```
src/
├── AssetPool.sol          # Protocol coordinator, registry, user entrypoint
├── AssetToken.sol         # Upgradeable ERC20 per asset (BeaconProxy)
├── ChainlinkCaller.sol    # Chainlink Functions integration layer
├── BrokerDollar.sol       # Internal USD-pegged base token
└── Governance/
    ├── RWAGovernor.sol    # OZ Governor
    └── BrokerGovernanceToken.sol

functions/
└── sources/
    ├── mintAsset.js       # Chainlink Functions: buy order via Alpaca API
    └── redeemAsset.js     # Chainlink Functions: sell order via Alpaca API
```

**AssetPool** is the user entrypoint and protocol registry. It owns the
`UpgradeableBeacon` and deploys each `AssetToken` as a `BeaconProxy`, enabling
atomic upgrades across all assets via governance. Ownership is held by the
`TimelockController`.

**AssetToken** manages the full request lifecycle per asset. Each mint or redeem
creates an `AssetRequest` stored in `requestIdToRequest`, with a deadline, escrow
accounting, and explicit status transitions.

**ChainlinkCaller** submits JavaScript source code to Chainlink's DON for execution.
The DON calls the Alpaca sandbox API, waits for order fill, and returns the filled
quantity. The callback routes the result to the correct `AssetToken` via
`requestToToken`.

---

## Request Lifecycle
```
PENDING → FULFILLED | ERROR | EXPIRED
```

**Mint flow:**
1. User calls `AssetPool.mintAsset(usdAmount, ticket, expectedAssetAmount)`
2. `BrokerDollar` is transferred to `AssetToken` (escrowed)
3. `ChainlinkCaller.requestMint` submits the Chainlink Functions request
4. DON executes `mintAsset.js` → places buy order on Alpaca → polls until filled
5. `ChainlinkCaller._fulfillRequest` receives filled quantity → calls `AssetToken.onFulfill`
6. `onFulfill` validates slippage bounds (±2%), then mints tokens or issues refund

**Redeem flow** mirrors mint in reverse: asset tokens are transferred to `AssetToken`,
a sell order is placed, and `BrokerDollar` is returned on fulfillment or the asset
tokens are refunded on failure.

**Expiry:** requests have a configurable timeout (default 1 hour, range 5 min–24 h).
Expired requests can be cleaned up by anyone via `cleanupExpiredRequests`, which
triggers a refund.

---

## Key Design Decisions

**Refund-first error handling.** Every failure path — API error, zero fill, slippage
violation, timeout, unexpected callback — triggers an immediate refund. User funds
are never trapped in a pending state indefinitely.

**Slippage bounds.** Users submit an `expectedAmount` alongside their request. On
fulfillment, the protocol enforces ±2% bounds. If the actual fill deviates beyond
this, the request is marked as error and refunded.

**BeaconProxy pattern.** All `AssetToken` instances share a single implementation
via `UpgradeableBeacon`. Governance can upgrade all asset tokens atomically with a
single transaction, without touching individual proxy addresses.

**Governance separation.** `AssetPool` is owned by `TimelockController`.
Privileged actions — listing assets, upgrading implementations, setting timeouts,
emergency pause — require a full governance proposal cycle: propose → vote → queue →
execute. The Timelock enforces a mandatory delay before execution.

**Rate limiting.** Users are subject to a 5-minute cooldown between requests
(`REQUEST_COOLDOWN`) to prevent spam and simplify accounting.

---

## Testing

Unit tests use a `MockChainlinkCaller` that exposes `fulfillRequest`,
`fulfillMintRequest`, and `fulfillRequestWithError` helpers, allowing synchronous
simulation of the async fulfillment flow in Foundry tests.
```bash
forge test -vv
```

Test coverage includes full mint/redeem lifecycle, slippage enforcement, expired
request cleanup, beacon upgrade verification, governance proposal flows
(propose → vote → queue → execute), and emergency pause/unpause.

---

## Frontend

Built with Next.js 14, wagmi v2, RainbowKit, and TypeScript on Arbitrum Sepolia.
Price data is sourced from the Alpaca market data API via a server-side proxy route.
Asset images are stored on IPFS via Pinata.
```bash
cd frontend
npm install
npm run dev
```

---

## Disclaimer

Experimental and unaudited. Uses Alpaca sandbox (no real money). Do not use in
production.
