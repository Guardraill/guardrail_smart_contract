# Guardrail — Technical Documentation

> **Version:** 0.1.0 · **Chain:** Monad · **Stack:** Rust · SolidJS · Solidity

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [System Architecture](#2-system-architecture)
3. [Smart Contracts](#3-smart-contracts)
   - 3.1 [AccessControl](#31-accesscontrol)
   - 3.2 [MultiSigAdmin](#32-multisigadmin)
   - 3.3 [AssetFactory](#33-assetfactory)
   - 3.4 [BaseAssetToken](#34-baseassettoken)
   - 3.5 [ComplianceDiamond](#35-compliancediamond)
   - 3.6 [Treasury](#36-treasury)
   - 3.7 [OracleDataBridge](#37-oracledatabridge)
   - 3.8 [MockUSDC](#38-mockusdc)
4. [Backend Service](#4-backend-service)
   - 4.1 [Technology Stack](#41-technology-stack)
   - 4.2 [Configuration & Environment](#42-configuration--environment)
   - 4.3 [API Modules](#43-api-modules)
   - 4.4 [Database Schema](#44-database-schema)
   - 4.5 [Services Layer](#45-services-layer)
   - 4.6 [Middleware & Security](#46-middleware--security)
5. [Frontend Application](#5-frontend-application)
   - 5.1 [Technology Stack](#51-technology-stack)
   - 5.2 [Routing Structure](#52-routing-structure)
   - 5.3 [Core Components](#53-core-components)
   - 5.4 [Library Modules](#54-library-modules)
6. [Core Workflows](#6-core-workflows)
   - 6.1 [User Authentication](#61-user-authentication)
   - 6.2 [Asset Onboarding (Admin)](#62-asset-onboarding-admin)
   - 6.3 [Asset Purchase Flow](#63-asset-purchase-flow)
   - 6.4 [Asset Redemption Flow](#64-asset-redemption-flow)
   - 6.5 [Compliance Checking](#65-compliance-checking)
   - 6.6 [Oracle Valuation Submission](#66-oracle-valuation-submission)
7. [Role-Based Access Control](#7-role-based-access-control)
8. [Compliance System](#8-compliance-system)
9. [Asset Lifecycle States](#9-asset-lifecycle-states)
10. [Nigerian Asset Catalog](#10-nigerian-asset-catalog)
11. [Account Abstraction (AA)](#11-account-abstraction-aa)
12. [Deployment & Infrastructure](#12-deployment--infrastructure)
13. [Testing](#13-testing)
14. [API Reference Summary](#14-api-reference-summary)

---

## 1. Project Overview

Guardrail is a **Real World Asset (RWA) tokenization platform** that brings traditional financial instruments — sovereign bonds, treasury bills, sukuk, and corporate paper — onto a public blockchain. The platform is designed with the Nigerian capital market as a primary target, though its architecture supports any jurisdiction.

**What it does:**

- Tokenizes real-world debt instruments as ERC-20 tokens on the Monad blockchain.
- Enforces investor compliance (KYC/AML, accreditation, jurisdiction restrictions) on-chain before every purchase, transfer, or redemption.
- Manages USDC-denominated subscriptions and redemptions through a non-custodial Treasury contract.
- Prices assets through a trusted oracle bridge that pushes off-chain Net Asset Values (NAVs) on-chain.
- Provides a full Web2-style user experience (Google login, embedded wallets, account abstraction) so end-users do not need to manage gas or private keys.
- Exposes a REST API consumed by both the frontend and third-party integrators.

**Key design principles:**

| Principle | Implementation |
|-----------|---------------|
| Compliance-first | Every on-chain action checks the `ComplianceDiamond` before execution |
| Upgradeable compliance | EIP-2535 Diamond pattern allows compliance rules to evolve without redeploying asset contracts |
| Gasless UX | ERC-4337 Account Abstraction bundles user operations so investors pay zero gas |
| Permissioned roles | A hierarchical on-chain `AccessControl` contract guards all privileged operations |
| Mirrored state | The Rust backend maintains a mirror of on-chain state in PostgreSQL for fast queries |

---

## 2. System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Frontend (SolidStart)                    │
│  Market Browse · Asset Detail · Portfolio · Admin Panel      │
└────────────────────────┬────────────────────────────────────┘
                         │ REST API (JSON/HTTP)
┌────────────────────────▼────────────────────────────────────┐
│               Backend (Rust / Axum)                          │
│  Auth · Assets · Compliance · Oracle · Treasury · Faucet     │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────────┐  │
│  │  PostgreSQL  │  │  Ethers-rs    │  │  AA Bundler RPC  │  │
│  │  (off-chain  │  │  (on-chain    │  │  (gasless txns)  │  │
│  │   mirror)    │  │   reads/write │  │                  │  │
│  └──────────────┘  └──────┬────────┘  └──────────────────┘  │
└──────────────────────────┼─────────────────────────────────┘
                           │ Monad RPC
┌──────────────────────────▼─────────────────────────────────┐
│                Smart Contracts (Solidity)                    │
│                                                             │
│  AccessControl ─────► AssetFactory ──► BaseAssetToken (N)   │
│       │                    │                  │             │
│       │           ComplianceDiamond ◄──────────┤             │
│       │                    │                  │             │
│       └──────────► Treasury ◄─────────────────┘             │
│                    OracleDataBridge                          │
└─────────────────────────────────────────────────────────────┘
```

The three repositories correspond to the three layers:

- **`smart_contract`** — Foundry project; all on-chain logic.
- **`backend`** — Rust/Axum server; orchestrates blockchain calls, mirrors state to PostgreSQL, exposes REST API.
- **`frontend`** — SolidStart SSR application; the user-facing web interface.

---

## 3. Smart Contracts

All contracts target `solidity ^0.8.28` and are built with **Foundry**. The project is deployed on the **Monad** EVM-compatible network (chain ID `4202` in testnet broadcasts).

### 3.1 AccessControl

**File:** `src/admin/contracts/AccessControl.sol`

The foundational permissioning contract. Every other contract holds an immutable reference to it and calls `hasRole()` before executing privileged logic.

**Defined roles (from `Roles.sol`):**

| Role constant | Who holds it | What it gates |
|---------------|-------------|---------------|
| `DEFAULT_ADMIN_ROLE` | Protocol deployer | Can manage all other role admins |
| `ADMIN_ROLE` | Guardrail operations team | Full administrative access to all contracts |
| `ISSUER_ROLE` | Authorized asset issuers | Can call `issue()` and `burn()` on asset tokens |
| `COMPLIANCE_ROLE` | Compliance officers | Manage investor whitelist & asset rules |
| `ORACLE_ROLE` | Trusted oracle wallets | Submit valuations to `OracleDataBridge` |
| `OPERATOR_ROLE` | Backend operator wallet | Executes controller transfers & gasless operations |
| `PAUSER_ROLE` | Emergency responders | Pause/unpause contracts |
| `TREASURY_ROLE` | Treasury service accounts | Manage treasury fund movements |

**Key functions:**

```solidity
hasRole(bytes32 role, address account) → bool
grantRole(bytes32 role, address account)   // onlyRole(adminRole)
revokeRole(bytes32 role, address account)  // onlyRole(adminRole)
```

---

### 3.2 MultiSigAdmin

**File:** `src/admin/contracts/MultiSigAdmin.sol`

A multi-signature governance contract that wraps the `AccessControl` contract for high-stakes operations (e.g., granting admin roles). Proposals are encoded using `ProposalEncoder.sol` and must reach a threshold of approvals before execution.

---

### 3.3 AssetFactory

**File:** `src/asset/contracts/AssetFactory.sol`

The factory responsible for deploying new tokenized asset contracts. It is the single on-chain registry of all Guardrail assets.

**State mappings:**

| Mapping | Key → Value | Purpose |
|---------|------------|---------|
| `assets` | `proposalId → address` | Prevents double-tokenization of the same proposal |
| `registeredAssetTypes` | `assetTypeId → bool` | Whitelists valid asset implementation templates |
| `assetTypeImplementations` | `assetTypeId → address` | Points to the ERC-20 implementation contract for cloning |
| `assetsByType` | `assetTypeId → address[]` | Groups assets by category |
| `allAssets` | `address[]` | Global registry |

**Key functions:**

```solidity
// Deploys a new BaseAssetToken and registers it in Treasury
createAsset(proposalId, assetTypeId, name, symbol, maxSupply, data)
    → tokenAddress
    // Caller: ISSUER_ROLE or ADMIN_ROLE; factory must not be paused

// Whitelists a new asset implementation template
registerAssetType(assetTypeId, assetTypeName, implementation)
    // Caller: ADMIN_ROLE

// Emergency controls
pauseFactory()   // ADMIN_ROLE
unpauseFactory() // ADMIN_ROLE
```

The `data` parameter passed to `createAsset` is ABI-encoded as an `AssetCreationConfig` struct containing subscription price, redemption price, self-service purchase flag, and a metadata hash.

---

### 3.4 BaseAssetToken

**File:** `src/asset/contracts/BaseAssetToken.sol`

The ERC-20 token contract that represents a single real-world asset. Each call to `AssetFactory.createAsset()` deploys one instance of this contract.

**Core properties:**

```solidity
uint256 public immutable proposalId;      // Links token back to the off-chain proposal
bytes32 public immutable assetTypeId;     // e.g. "NG_SOV_TBILL"
uint256 public immutable maxSupply;       // Hard cap on tokens that can be issued

uint256 public pricePerToken;             // Subscription price (USDC base units)
uint256 public redemptionPricePerToken;   // Redemption price (USDC base units)
AssetState public assetState;             // Active | Paused | Matured | Archived
bool public selfServicePurchaseEnabled;   // Whether investors can self-subscribe
```

**Asset lifecycle functions:**

```solidity
// Mint tokens to an investor (checks compliance first)
issue(address to, uint256 amount, bytes data)   // ISSUER_ROLE

// Burn tokens after a redemption reservation is confirmed
burn(address from, uint256 amount)              // ISSUER_ROLE

// Investor initiates a redemption request
redeem(uint256 amount)                           // Any holder; whenRedeemable

// Admin settles / cancels pending redemption
processRedemption(address investor, uint256 amount)
cancelRedemption(address investor, uint256 amount)

// Purchase with USDC (if selfServicePurchaseEnabled)
purchase(uint256 amount)                         // Any investor; compliance checked

// Yield distribution
distributeYield(uint256 totalYieldAmount)        // TREASURY_ROLE or ADMIN_ROLE
claimYield()                                     // Any holder
```

**Compliance gate:** Before `issue()` or `purchase()` executes, it calls `complianceRegistry.canSubscribe(investor, asset, amount)`. Before any ERC-20 transfer, it calls `complianceRegistry.canTransfer(from, to, asset, amount)`. Any `false` response reverts the transaction.

**Yield accounting:** Uses a magnified yield-per-share algorithm (similar to EIP-1973) to distribute yield proportionally to all holders without iterating over addresses.

---

### 3.5 ComplianceDiamond

**Files:** `src/compliance/`

The compliance system is built as an **EIP-2535 Diamond** proxy. This means the permanent contract address (the Diamond) delegates calls to swappable facet contracts, allowing compliance rules to be upgraded without affecting the asset token addresses that reference it.

**Facets:**

| Facet | Responsibility |
|-------|---------------|
| `ComplianceCheckFacet` | Implements `canSubscribe`, `canTransfer`, `canRedeem` — the three gates called by asset tokens |
| `ComplianceRulesFacet` | Stores and retrieves per-asset rules (transfers enabled, redemptions enabled, min investment, accreditation required, etc.) |
| `ComplianceWhitelistFacet` | Manages the investor registry (verified, accredited, frozen, jurisdiction, expiry) |
| `DiamondCutFacet` | Allows the owner to add/replace/remove facets (the EIP-2535 upgrade mechanism) |
| `DiamondLoupeFacet` | Introspection: returns which functions are on which facet |
| `OwnershipFacet` | ERC-173 ownership for diamond administration |

**Storage:** All compliance data is stored in a single namespaced slot via `LibComplianceStorage` to avoid storage collisions between facets.

**Investor record fields:**

```
is_verified   — KYC verified
is_accredited — Meets accreditation criteria
is_frozen     — Blocked from all actions
valid_until   — Timestamp after which verification expires
jurisdiction  — ISO country/region code
external_ref  — Off-chain KYC provider reference ID
```

---

### 3.6 Treasury

**File:** `src/treasury/contracts/Treasury.sol`

A non-custodial escrow that holds the USDC payment token on behalf of all registered asset tokens.

**Balance tracking:**

```
assetBalances[asset]            — Freely available balance for the asset
reservedYieldBalances[asset]    — Funds earmarked for yield distribution
reservedRedemptionBalances[asset] — Funds held for pending redemptions
totalTrackedBalance             — Sum of all asset balances
totalReservedYield              — Sum of all yield reserves
totalReservedRedemptions        — Sum of all redemption reserves
```

**Key operations called by asset tokens:**

```solidity
collectPurchaseFunds(investor, amount)     // Pull USDC from investor wallet
reserveRedemption(investor, amount)        // Lock USDC for pending redemption
releaseRedemption(investor, amount)        // Pay USDC to investor on settlement
cancelRedemption(investor, amount)         // Unlock reserved USDC back to asset balance
reserveYield(amount)                       // Move funds into yield reserve
distributeYield(investor, amount)          // Pay out yield to a holder
```

Only registered asset token addresses (registered via `registerAssetToken` at creation time) can call treasury fund operations.

---

### 3.7 OracleDataBridge

**File:** `src/oracle/contracts/OracleDataBridge.sol`

Bridges off-chain valuations and documents onto the chain for use by the asset pricing system.

**Core concepts:**

- **Trusted oracles** — Addresses whitelisted by `ADMIN_ROLE` that are authorized to submit valuations.
- **Valuation** — A snapshot of `assetValue` (total NAV in base currency) and `navPerToken` (per-token NAV), plus a reference ID linking it to an off-chain data source.
- **Documents** — IPFS/IPNS content hashes anchored on-chain by document type (e.g., `PROSPECTUS`, `AUDITED_ACCOUNTS`).

```solidity
// Submit a NAV update for an asset
submitValuation(asset, assetValue, navPerToken, referenceId)  // onlyOracle

// Anchor a document hash for an asset
anchorDocument(asset, documentType, documentHash)              // onlyOracle

// Register or remove a trusted oracle address
setTrustedOracle(oracle, trusted)                              // onlyAdmin

// Validate that a stored valuation is not stale (max age: 90 days)
assertValuationFresh(asset)
```

---

### 3.8 MockUSDC

**File:** `src/mocks/MockUSDC.sol`

A simple ERC-20 token deployed on the testnet that simulates USDC. The faucet service mints tokens to test investors via the backend.

---

## 4. Backend Service

### 4.1 Technology Stack

| Component | Technology | Notes |
|-----------|-----------|-------|
| Language | Rust (edition 2024, MSRV 1.94) | |
| Web framework | Axum 0.8 | Async HTTP server |
| Database | PostgreSQL via SQLx 0.8 | Compile-time verified queries |
| Blockchain client | Ethers-rs 2.0 | EVM interaction |
| Auth | JWT (`jsonwebtoken` 9.3) + Google OIDC | |
| Async runtime | Tokio 1.50 (multi-thread) | |
| Encryption | AES-GCM 0.10 | AA wallet key encryption |
| File storage | Filebase (S3-compatible + IPFS) | Asset metadata / documents |

### 4.2 Configuration & Environment

The server is configured entirely through environment variables (loaded via `dotenvy`). Key variables:

**Network & Chain:**
```
MONAD_RPC_URL            — Primary Monad JSON-RPC endpoint
MONAD_RPC_URLS           — Comma-separated fallback endpoints
MONAD_CHAIN_ID           — Chain ID (e.g. 4202 for testnet)
OPERATOR_PRIVATE_KEY     — Backend operator's signing key
```

**Contract Addresses:**
```
ACCESS_CONTROL_ADDRESS
ASSET_FACTORY_ADDRESS
COMPLIANCE_REGISTRY_ADDRESS
TREASURY_ADDRESS
ORACLE_DATA_BRIDGE_ADDRESS
PAYMENT_TOKEN_ADDRESS
```

**Account Abstraction:**
```
AA_BUNDLER_RPC_URL
AA_ENTRY_POINT_ADDRESS
AA_SIMPLE_ACCOUNT_FACTORY_ADDRESS
AA_USER_OPERATION_POLL_INTERVAL_MS
AA_USER_OPERATION_TIMEOUT_MS
AA_OWNER_ENCRYPTION_KEY           — AES-GCM key for encrypting embedded wallet seeds
AA_OWNER_ENCRYPTION_KEY_VERSION
```

**Auth:**
```
GOOGLE_CLIENT_ID
GOOGLE_JWKS_URL
JWT_SECRET
JWT_TTL_HOURS
ADMIN_WALLET_ADDRESSES   — Comma-separated addresses with admin-level API access
```

**Faucet:**
```
FAUCET_USDC_AMOUNT          — Tokens dispensed per request
FAUCET_USDC_COOLDOWN_SECS   — Cooldown period between requests per user
```

**Storage (Filebase/IPFS):**
```
FILEBASE_BUCKET_NAME
FILEBASE_S3_ENDPOINT
FILEBASE_ACCESS_KEY / FILEBASE_SECRET_KEY
FILEBASE_GATEWAY_BASE_URL
FILEBASE_IPFS_RPC_URL / FILEBASE_IPFS_RPC_TOKEN
```

---

### 4.3 API Modules

The Axum router is assembled in `src/app.rs` and groups endpoints into logical modules with distinct access levels.

#### Authentication — `/auth`

| Method | Endpoint | Auth Required | Description |
|--------|----------|--------------|-------------|
| `POST` | `/auth/google/sign-in` | No | Exchange Google OIDC credential for a JWT |
| `POST` | `/auth/wallet/challenge` | No | Request a sign challenge for a wallet address |
| `POST` | `/auth/wallet/connect` | No | Submit signed challenge to authenticate and get JWT |
| `GET` | `/auth/me` | User JWT | Return the authenticated user's profile |

#### Assets — `/assets`

**Public endpoints (no auth):**

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/assets/factory` | Factory contract status (paused, total created) |
| `GET` | `/assets/types` | List all registered asset types |
| `GET` | `/assets/types/{asset_type_id}` | Single asset type detail |
| `GET` | `/assets` | Paginated asset catalog (filterable by type, state, featured) |
| `GET` | `/assets/by-type/{asset_type_id}` | Assets filtered by type |
| `GET` | `/assets/{asset_address}` | Asset summary |
| `GET` | `/assets/{asset_address}/detail` | Full asset detail including oracle valuation, treasury data |
| `GET` | `/assets/{asset_address}/history` | Price history |
| `GET` | `/assets/slug/{slug}`, `/assets/proposals/{proposal_id}` | Alternative lookups |
| `GET` | `/assets/{asset_address}/holders/{wallet_address}` | Investor's holding state for an asset |
| `POST` | `/assets/{asset_address}/preview/purchase` | Simulate a purchase (quote) |
| `POST` | `/assets/{asset_address}/preview/redemption` | Simulate a redemption (quote) |

**User endpoints (JWT required):**

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/assets/{asset_address}/purchase` | Execute a purchase (triggers AA transaction) |
| `POST` | `/assets/{asset_address}/redeem` | Request redemption |
| `POST` | `/assets/{asset_address}/yield/claim` | Claim accrued yield |

**Admin endpoints (Admin JWT required):**

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/admin/assets/types` | Register a new asset type |
| `DELETE` | `/admin/assets/types/{id}` | Unregister an asset type |
| `POST` | `/admin/assets` | Create a new tokenized asset |
| `PUT` | `/admin/assets/{asset_address}/pricing` | Update subscription/redemption price |
| `PUT` | `/admin/assets/{asset_address}/state` | Transition asset state |
| `PUT` | `/admin/assets/{asset_address}/catalog` | Update catalog metadata |
| `POST` | `/admin/assets/{asset_address}/issue` | Issue tokens to an address |
| `POST` | `/admin/assets/{asset_address}/burn` | Burn tokens from an address |

#### Compliance — `/compliance`

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/compliance/investors/{wallet}` | Public | Get investor compliance record |
| `GET` | `/compliance/assets/{asset}/rules` | Public | Get compliance rules for an asset |
| `GET` | `/compliance/assets/{asset}/jurisdictions/{j}` | Public | Check jurisdiction restriction |
| `POST` | `/compliance/check/subscribe` | Public | Simulate a subscription compliance check |
| `POST` | `/compliance/check/transfer` | Public | Simulate a transfer compliance check |
| `POST` | `/compliance/check/redeem` | Public | Simulate a redemption compliance check |
| `PUT` | `/admin/compliance/investors/{wallet}` | Admin | Upsert investor record |
| `POST` | `/admin/compliance/investors/batch` | Admin | Batch upsert investors |
| `PUT` | `/admin/compliance/assets/{asset}/rules` | Admin | Set asset compliance rules |
| `PUT` | `/admin/compliance/assets/{asset}/jurisdictions/{j}` | Admin | Set jurisdiction restriction |

#### Oracle — `/oracle`

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/oracle/trusted-oracles/{oracle_address}` | Public | Check if address is a trusted oracle |
| `GET` | `/oracle/assets/{asset_address}/valuation` | Public | Get latest valuation for an asset |
| `GET` | `/oracle/assets/{asset_address}/documents/{document_type}` | Public | Get anchored document hash |
| `PUT` | `/admin/oracle/trusted-oracles/{oracle_address}` | Admin | Register/deregister a trusted oracle |
| `POST` | `/admin/oracle/valuations` | Admin | Submit a new valuation |
| `POST` | `/admin/oracle/valuations/sync-pricing` | Admin | Submit valuation and update asset pricing in one call |
| `PUT` | `/admin/oracle/assets/{asset_address}/documents/{document_type}` | Admin | Anchor a document hash |

#### Treasury — `/treasury`

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/treasury` | Public | Overall treasury status |
| `GET` | `/treasury/assets/{asset_address}` | Public | Treasury state for a specific asset |
| `POST` | `/admin/treasury/...` | Admin | Treasury management operations |

#### Faucet — `/faucet`

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/faucet/usdc/balance` | Public | Check USDC balance for an address |
| `POST` | `/faucet/usdc` | User JWT | Dispense testnet USDC (subject to cooldown) |

#### Market — `/markets` (read-only proxy)

The market module proxies read requests to a separate prediction market service. It exposes category, tag, event, and market browse endpoints used by the frontend's public browser.

---

### 4.4 Database Schema

The PostgreSQL database mirrors on-chain state and stores off-chain metadata. All tables use UUIDs as primary keys where applicable and record `created_at` / `updated_at` timestamps.

**Auth tables:**

```
users                    — Core user record (id, email, display_name, avatar_url)
google_identities        — Links users to Google sub identifiers
wallet_accounts          — EVM wallet addresses associated with users
wallet_challenges        — Ephemeral sign challenges for wallet authentication
```

**Asset tables:**

```
asset_types              — Registered asset type templates
assets                   — Full asset state mirror (prices, state, supply, addresses)
asset_catalog_entries    — Metadata (name, slug, image, summary, tags, featured flag)
asset_price_history      — Time-series subscription/redemption price records
```

**Compliance tables:**

```
compliance_investors               — Per-wallet KYC record
compliance_asset_rules             — Per-asset trading rules
compliance_jurisdiction_restrictions — Per-asset, per-jurisdiction block list
```

**Oracle & Treasury tables:**

```
trusted_oracles                    — Trusted oracle registry
asset_valuations                   — Latest NAV record per asset
asset_valuation_history            — Time-series valuation records
oracle_documents                   — Document type → hash anchoring
treasury_status                    — Overall treasury balance snapshot
treasury_assets                    — Per-asset treasury balance snapshot
```

**Faucet tables:**

```
faucet_requests  — Records every dispense (user_id, amount, tx_hash, timestamps)
```

---

### 4.5 Services Layer

The `src/service/` directory contains the business logic that sits between HTTP controllers and the raw database / blockchain calls.

| Service | File | Responsibility |
|---------|------|---------------|
| Auth | `service/auth.rs` | JWT issuance, Google OIDC verification, wallet challenge sign/verify |
| AA (Account Abstraction) | `service/aa.rs` | Build and submit ERC-4337 `UserOperation` objects through the bundler |
| Admin Auth | `service/admin_auth.rs` | Validate admin wallet addresses against the environment config |
| Chain | `service/chain.rs` | Low-level Monad RPC helpers, nonce management, receipt polling |
| RPC | `service/rpc.rs` | HTTP JSON-RPC client with fallback URL support |
| Asset (service) | `service/asset/` | Encode ABI calls to `BaseAssetToken`; read state from chain |
| Compliance (service) | `service/compliance/` | ABI calls to `ComplianceDiamond` facets |
| Treasury (service) | `service/treasury/` | ABI calls to `Treasury` contract |
| Oracle (service) | `service/oracle/` | ABI calls to `OracleDataBridge` |
| Liquidity (service) | `service/liquidity/` | Order book / liquidity queries |
| Gasless | `service/gasless/` | Constructs paymaster-sponsored user operations |
| Faucet | `service/faucet.rs` | Calls MockUSDC `mint()` on testnet |
| Market | `service/market.rs` | HTTP proxy to external prediction market API |
| Crypto | `service/crypto.rs` | AES-GCM encryption/decryption for embedded wallet seeds |
| Upload | `service/upload.rs` | Filebase S3+IPFS upload helpers |
| Browser | `service/browser.rs` | Public browse/search aggregation |

---

### 4.6 Middleware & Security

Two Axum middleware functions gate protected routes:

**`require_auth`** (`middleware/user.rs`): Extracts the `Authorization: Bearer <jwt>` header, validates the JWT signature and expiry, resolves the user from the database, and injects the user record into the request extension. Returns `401 Unauthorized` if the token is missing, invalid, or expired.

**`require_admin`** (`middleware/admin.rs`): Calls `require_auth` first, then checks that the authenticated user's wallet address appears in the `ADMIN_WALLET_ADDRESSES` environment list. Returns `403 Forbidden` if the user is not an admin.

All routes benefit from:
- **CORS layer** configured from `CORS_ALLOWED_ORIGINS`.
- **Trace layer** (Tower HTTP) that logs latency for every request at INFO level.

---

## 5. Frontend Application

### 5.1 Technology Stack

| Component | Technology | Notes |
|-----------|-----------|-------|
| Framework | SolidJS 1.9 + SolidStart 2.0 | SSR-capable reactive framework |
| Router | `@solidjs/router` 0.15 | File-based routing via `FileRoutes` |
| Server runtime | Nitro (via `@solidjs/vite-plugin-nitro-2`) | SSR + API routes |
| Build tool | Vite 7 | |
| Charting | `@visx/shape`, `@visx/scale`, `@visx/curve` | D3-based chart primitives |
| Runtime | Node ≥ 22 | |

---

### 5.2 Routing Structure

```
/                          → Market home (featured & trending markets)
/search                    → Full-text market search
/tags                      → Tag directory
/about                     → About page
/portfolio                 → Authenticated user portfolio

/markets                   → Market browse list
/markets/[marketId]        → Market detail page
/markets/by-condition/[conditionId] → Market lookup by condition ID

/events/[eventId]          → Event detail (grouped markets)
/event/[eventSlug]/[marketSlug] → SEO-friendly event + market URL
/event/[eventSlug]         → Event landing page

/assets                    → Asset catalog browse
/assets/[assetAddress]     → Asset detail (price, NAV, purchase/redeem UI)
/assets/slug/[slug]        → Asset by slug
/assets/proposals/[proposalId] → Asset by proposal

/categories                → Category directory
/categories/[slug]         → Category detail with filtered markets

/google/callback           → OAuth redirect handler

/[...404]                  → Catch-all 404 page
```

---

### 5.3 Core Components

**`Navbar`** (`src/components/Navbar.tsx`)

The application shell. Handles:
- Top-level navigation tabs with dynamic category/tag menus loaded on hover.
- Search bar with 200 ms debounce, minimum 2 characters, and a 6-result limit backed by the `/markets` search endpoint.
- Authentication state: shows login button when unauthenticated; shows user avatar, balance, and deposit button when logged in.
- Wallet balance display (USDC) pulled from the faucet balance endpoint.
- **AuthModal** — triggered by the login button; offers Google Sign-In or wallet connect.
- **DepositModal** — for adding funds.
- **HowItWorksModal** — product explainer.

**`AssetDetailScreen`** (`src/components/asset-detail/`)

The full asset detail page with:
- Hero section (name, type, price, NAV, state badge).
- Price history chart (time range selectable: 1D, 1W, 1M, 3M, 1Y).
- Stats grid (supply, holders, yield metrics).
- **AssetTradePanel** — buy/sell widget; calls `/assets/{address}/purchase` or `/assets/{address}/redeem`.
- Reference panels (oracle documents, sources).

**`MarketDetailPage`** (`src/components/market-detail/`)

Prediction market detail page including:
- Price panel with live order book data.
- Activity feed (recent trades).
- Comments section.
- Related markets panel.
- Liquidity card.
- Trade panel for buying/selling positions.

**`PublicBrowser`** (`src/components/public-browser/`)

Browsing and discovery screens: category directory, tag directory, market search, grouped market grids, and summary tile grids for the home page.

---

### 5.4 Library Modules

The `src/lib/` directory contains typed API clients and utility functions. Each sub-module exposes a client instance and re-exports its types.

| Module | Client | Key operations |
|--------|--------|---------------|
| `auth` | `authClient` | `googleSignIn`, `walletChallenge`, `walletConnect`, `me` |
| `asset` | `assetClient` | `listAssets`, `fetchAssetDetail`, `fetchAssetHistory`, `purchaseAsset`, `redeemAsset` |
| `market` | `marketClient` | `listMarkets`, `searchMarkets`, `listCategories`, `listTags`, `fetchEvent` |
| `order` | `orderClient` | `createOrder`, `cancelOrder` |
| `compliance` | `complianceClient` | `checkSubscribe`, `checkTransfer`, `getInvestor` |
| `oracle` | `oracleClient` | `getValuation`, `getDocument` |
| `treasury` | `treasuryClient` | `getTreasuryStatus`, `getTreasuryAsset` |
| `faucet` | `faucetClient` | `faucetUsdc`, `getUsdcBalance` |
| `admin` | `adminClient` | Admin CRUD for assets, compliance, oracle, treasury |

**`src/lib/wallet.ts`** — Manages the user's preferred wallet provider (stored in `localStorage`). Supports injected browser wallets and managed (AA) wallets.

**`src/lib/auth/session.ts`** — Reads/writes the JWT auth session to `localStorage` with typed helper functions (`readStoredAuthSession`, `writeStoredAuthSession`, `clearStoredAuthSession`).

---

## 6. Core Workflows

### 6.1 User Authentication

```
Option A — Google Sign-In
──────────────────────────
1. Frontend renders Google One Tap button.
2. On click, Google returns an OIDC `credential` string.
3. Frontend POSTs credential to POST /auth/google/sign-in.
4. Backend verifies the JWT against Google's JWKS endpoint.
5. If the Google `sub` is new, a user record is created in the DB.
6. Backend issues and returns a Guardrail JWT.
7. Frontend stores JWT in localStorage; subsequent API calls include
   Authorization: Bearer <token>.

Option B — Wallet Connect (EIP-4361 / SIWE-style)
──────────────────────────────────────────────────
1. Frontend POSTs wallet_address to POST /auth/wallet/challenge.
2. Backend creates and returns a time-limited sign challenge message.
3. Frontend asks the user's wallet to sign the message.
4. Frontend POSTs challenge_id + signature to POST /auth/wallet/connect.
5. Backend verifies the signature, resolves the user, returns JWT.
```

---

### 6.2 Asset Onboarding (Admin)

```
1.  Admin calls POST /admin/assets/types
    → Backend calls AssetFactory.registerAssetType() on-chain.
    → DB record created in asset_types.

2.  Admin calls POST /admin/assets with full metadata:
    → Backend calls AssetFactory.createAsset() on-chain.
    → New BaseAssetToken deployed; Treasury.registerAssetToken() called.
    → DB records created in assets + asset_catalog_entries.

3.  Admin calls PUT /admin/compliance/assets/{address}/rules
    → Backend calls ComplianceDiamond.setAssetRules() on-chain.
    → DB record created in compliance_asset_rules.

4.  Admin calls PUT /admin/oracle/valuations/sync-pricing
    → Backend calls OracleDataBridge.submitValuation() on-chain.
    → Backend calls BaseAssetToken.setPrice() to sync on-chain price.
    → DB records in asset_valuations + asset_price_history updated.

5.  Asset is now live for investor subscriptions.
```

---

### 6.3 Asset Purchase Flow

```
1.  Investor views asset detail page.
2.  Frontend calls POST /assets/{address}/preview/purchase (optional quote).
3.  Investor clicks "Buy"; frontend calls POST /assets/{address}/purchase.
4.  Backend performs compliance pre-check:
        ComplianceDiamond.canSubscribe(investor, asset, amount)
5.  If approved, backend builds an ERC-4337 UserOperation:
        a. Approve USDC to Treasury
        b. Call BaseAssetToken.purchase(amount)
6.  Backend sends UserOperation to the AA bundler.
7.  BaseAssetToken.purchase() executes on-chain:
        a. Compliance checked again (on-chain).
        b. Treasury.collectPurchaseFunds(investor, totalCost) called.
        c. Tokens minted to investor.
8.  Backend receives receipt; DB state synced.
9.  Frontend reflects updated balance.
```

---

### 6.4 Asset Redemption Flow

```
1.  Investor requests redemption via frontend.
2.  Frontend calls POST /assets/{address}/redeem.
3.  Backend checks ComplianceDiamond.canRedeem(investor, asset, amount).
4.  Backend submits UserOperation calling BaseAssetToken.redeem(amount):
        a. Compliance checked on-chain.
        b. Pending redemption recorded in token contract.
        c. Treasury.reserveRedemption(investor, amount) called —
           USDC locked in treasury.
5.  Admin later calls POST /admin/assets/{address}/redemptions/process:
        a. Backend calls BaseAssetToken.processRedemption().
        b. Tokens burned.
        c. Treasury.releaseRedemption(investor, amount) — USDC sent to investor.
```

---

### 6.5 Compliance Checking

All three check functions follow the same pattern. `canSubscribe` as an example:

```
Input:  investor wallet address, asset address, USDC amount
Logic:
  1. Investor must exist and is_verified = true.
  2. Investor must not be is_frozen.
  3. Investor's valid_until must be in the future.
  4. Investor's jurisdiction must not be restricted for this asset.
  5. If asset requires_accreditation, investor.is_accredited must be true.
  6. Asset subscriptions_enabled must be true.
  7. USDC amount must be ≥ asset min_investment.
  8. Investor's current balance + amount must be ≤ asset max_investor_balance.
Output: bool (true = allowed)
```

---

### 6.6 Oracle Valuation Submission

```
1.  Admin/oracle service calls POST /admin/oracle/valuations/sync-pricing.
    Body: { asset_address, asset_value, nav_per_token, reference_id }

2.  Backend verifies caller is admin.

3.  Backend calls OracleDataBridge.submitValuation() on-chain:
    → Valuation stored in _valuations[asset].
    → ValuationSubmitted event emitted.

4.  Backend calls BaseAssetToken.setPrice(navPerToken) on-chain:
    → pricePerToken updated.

5.  Backend inserts record in asset_valuations + asset_valuation_history.

6.  Frontend reflects new NAV on asset detail page.
```

---

## 7. Role-Based Access Control

The access control hierarchy flows from the least privileged to the most:

```
DEFAULT_ADMIN_ROLE  ─── manages ──► ADMIN_ROLE
ADMIN_ROLE          ─── manages ──► ISSUER_ROLE
ADMIN_ROLE          ─── manages ──► COMPLIANCE_ROLE
ADMIN_ROLE          ─── manages ──► ORACLE_ROLE
ADMIN_ROLE          ─── manages ──► OPERATOR_ROLE
ADMIN_ROLE          ─── manages ──► PAUSER_ROLE
ADMIN_ROLE          ─── manages ──► TREASURY_ROLE
```

In practice the backend operator wallet holds `OPERATOR_ROLE` for day-to-day transaction signing. Human admins hold `ADMIN_ROLE`. The `DEFAULT_ADMIN_ROLE` holder can replace admin keys in an emergency.

On the API side, the distinction is simpler: any authenticated user can reach user-protected endpoints; only wallet addresses listed in `ADMIN_WALLET_ADDRESSES` can reach admin-protected endpoints.

---

## 8. Compliance System

The compliance system has two layers that must both be satisfied for any transaction to proceed.

**Layer 1 — Off-chain pre-check (backend):** Before submitting a transaction, the backend calls the corresponding compliance check endpoint against its PostgreSQL mirror. This is a fast, read-only check that catches most failures before spending gas.

**Layer 2 — On-chain enforcement (smart contract):** The `BaseAssetToken` calls `complianceRegistry.canSubscribe/canTransfer/canRedeem` inside the transaction. This is the authoritative check and cannot be bypassed.

**Rule precedence for `canSubscribe`:**

1. Investor not found → DENY
2. Investor is frozen → DENY
3. Investor not verified → DENY
4. Investor verification expired (`valid_until` < now) → DENY
5. Investor's jurisdiction is restricted for this asset → DENY
6. Asset subscriptions disabled → DENY
7. Asset requires accreditation, investor not accredited → DENY
8. Amount < `min_investment` → DENY
9. Current balance + amount > `max_investor_balance` → DENY
10. All checks pass → ALLOW

---

## 9. Asset Lifecycle States

Each `BaseAssetToken` has an `AssetState` enum:

| State | Meaning | Subscriptions | Transfers | Redemptions |
|-------|---------|--------------|-----------|-------------|
| `Active` | Accepting investors | ✅ | ✅ (if compliance allows) | ✅ |
| `Paused` | Operations suspended | ❌ | ❌ | ❌ |
| `Matured` | Instrument reached maturity | ❌ | ✅ | ✅ |
| `Archived` | Fully wound down | ❌ | ❌ | ❌ |

State transitions are executed by the backend admin API (`PUT /admin/assets/{address}/state`) which calls `BaseAssetToken.setAssetState()` on-chain.

---

## 10. Nigerian Asset Catalog

The platform ships with a pre-defined seed catalog for Nigerian financial instruments. This is managed via `docs/nigeria-admin-asset-seeds.json`. The supported asset types reflect the Nigerian Debt Management Office's (DMO) domestic debt instruments:

| Asset Type ID | Asset Type Name | Description |
|---------------|----------------|-------------|
| `NG_SOV_TBILL` | Nigeria Treasury Bill | Short-term sovereign debt (91, 182, 364 day) |
| `NG_SOV_BOND` | FGN Sovereign Bond | Long-term Federal Government of Nigeria bonds |
| `NG_SOV_SUKUK` | FGN Sovereign Sukuk | Sharia-compliant sovereign financing instruments |
| `NG_CORP_BOND` | Nigeria Corporate Bond | Investment-grade corporate debt |
| `NG_COMM_PAPER` | Nigeria Commercial Paper | Short-term corporate debt (< 270 days) |
| `NG_EUROBOND` | Nigeria Eurobond | USD-denominated external sovereign debt |
| `NG_MONEY_MARKET` | Nigeria Money Market Fund | Pooled short-term instruments |

The onboarding flow for each asset follows three admin API steps:

1. `POST /admin/assets/types` — Register the asset type with its implementation address.
2. `POST /admin/assets` — Create the specific instrument with pricing and catalog metadata.
3. `PUT /admin/assets/{address}/pricing` — Update prices as market conditions change.

---

## 11. Account Abstraction (AA)

Guardrail uses **ERC-4337 Account Abstraction** to deliver a gasless experience. Users never need to hold the native gas token.

**Key components:**

- **SimpleAccount factory** (`AA_SIMPLE_ACCOUNT_FACTORY_ADDRESS`) — Deploys ERC-4337 smart accounts for new users.
- **Bundler RPC** (`AA_BUNDLER_RPC_URL`) — Accepts `UserOperation` objects and bundles them into on-chain transactions.
- **EntryPoint** (`AA_ENTRY_POINT_ADDRESS`) — The ERC-4337 singleton entry point contract that validates and executes user operations.
- **Paymaster** — A paymaster contract sponsors gas so users pay zero native token.
- **Embedded wallets** — For users who authenticate via Google (no external wallet), the backend generates and AES-GCM encrypts a private key stored in the database. The encrypted seed is decrypted only when signing a `UserOperation`.

**UserOperation flow:**

```
1. Backend constructs the call data (e.g., ERC-20 approve + asset purchase).
2. Backend fetches the user's smart account nonce from the EntryPoint.
3. Backend builds the UserOperation struct.
4. Backend signs the operation with the user's embedded wallet key.
5. Backend sends eth_sendUserOperation to the bundler.
6. Backend polls with eth_getUserOperationReceipt until confirmed or timeout.
```

The AA smoke test binary (`src/bin/aa_smoke.rs`) can be run independently to verify AA infrastructure is operational.

---

## 12. Deployment & Infrastructure

### Smart Contracts

Contracts are deployed with Foundry deploy scripts in `script/`:

| Script | What it deploys |
|--------|----------------|
| `DeployMultiSigAdmin.s.sol` | AccessControl + MultiSigAdmin |
| `DeployComplianceDiamond.s.sol` | ComplianceDiamond + all facets |
| `DeployTestnet.s.sol` | Full testnet stack including MockUSDC, Treasury, OracleDataBridge, AssetFactory |

Broadcast artifacts in `broadcast/` record deployed addresses for chain ID `4202` (Monad testnet).

### Backend

The backend is a single Rust binary (`guardrailbackend`). It:
1. Loads environment variables from `.env` or the system environment.
2. Creates a PostgreSQL connection pool.
3. Runs `sqlx::migrate!()` to apply any pending migrations automatically on startup.
4. Binds to `HOST:PORT` and serves the Axum router.

### Frontend

The SolidStart app is deployed to **Vercel** (see `vercel.json`). It supports SSR via the Nitro server runtime. Build command: `vite build`; start command: `vite start`.

---

## 13. Testing

### Smart Contracts (Foundry)

Test files in `test/`:

| Test file | Coverage area |
|-----------|--------------|
| `ComplianceDiamond.t.sol` | Facet interactions, whitelist logic, rule enforcement |
| `OracleDataBridge.t.sol` | Valuation submission, staleness checks, document anchoring |
| `PurchaseFlow.t.sol` | End-to-end: issue → purchase → transfer → redeem including compliance gating |

Run tests with:
```bash
forge test
```

CI pipeline defined in `.github/workflows/test.yml`.

### Backend (Rust)

Unit tests for individual service functions are co-located with source files. Integration tests use SQLx's test transaction support to avoid polluting the database.

```bash
cargo test
```

### Frontend (Node)

The frontend's library layer has test coverage using Node's built-in test runner (`--experimental-strip-types`):

```bash
npm test
```

Test files follow the `*.test.ts` naming convention and use a fetch mock utility (`test/http.ts`) to simulate backend responses without network calls.

---

## 14. API Reference Summary

**Base URL:** Configured per environment (e.g., `https://api.guardrail.io`)

**Authentication header:** `Authorization: Bearer <jwt>`

**Common response codes:**

| Code | Meaning |
|------|---------|
| `200` | Success |
| `201` | Created |
| `400` | Bad request / validation error |
| `401` | Missing or invalid JWT |
| `403` | Authenticated but insufficient role |
| `404` | Resource not found |
| `409` | Conflict (e.g., proposal already tokenized) |
| `500` | Internal server error |

**Pagination:** List endpoints accept `limit` (default 20, max 100) and `offset` query parameters. Responses include a `total` count field.

**Amount encoding:** All USDC and token amounts are passed as decimal strings (not integers) to avoid JavaScript precision loss. The backend parses them using Rust's `rust_decimal` crate. Example: `"1000000"` = 1 USDC (6 decimals).

---

# Contributors
```

 Augustine Aniobasi | github.com/AugustineAniobasi | augustineaniobasi@gmail.com
 Onyinye Achomadu  | github.com/onyillto | achomaduonyinye@gmail.com
 Joy Egbala         | github.com/JSE19 | egbalajoy@gmail.com
 Akinola Akinbusola | github.com/Ololajaco |  
 Kingsley Aigbojie  | github.com/Geniuska275 | aigbojie2020@gmail.com
 
 
 ```
