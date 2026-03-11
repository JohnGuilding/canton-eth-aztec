# Prototype A — Canton-like Multiparty Trade on Aztec

A tight hackathon MVP for an **Aztec-only** protocol that splits a trade object across:

1. **Public coordination plane** — headers, lifecycle, stakeholder roots, policy hashes, settlement references, disclosure receipts.
2. **Private data plane** — confidential trade fields using Aztec-native private note/nullifier mental models.
3. **Disclosure / proof plane** — selective disclosure bundles and proof-only compliance assertions with public receipts.

This repo is deliberately practical:

- a clear protocol model
- policy and schema files
- Noir/Aztec-inspired contract/module stubs
- a **working TypeScript simulator/demo** that exercises the flow end to end
- a **minimal automated test suite** for the simulator behavior

## Why a simulator?

Aztec app contracts and Noir integration usually need the Aztec toolchain and network setup that are not available in this environment. So this MVP ships:

- **architecture-faithful Aztec-oriented source** under `src/aztec/`
- **runnable protocol demo** under `src/` that models the same public/private/disclosure behavior and emits the required public events
- **Node/TypeScript tests** under `test/` that validate simulator logic only

That gives a hackathon team something they can run immediately while keeping a clean path toward real Aztec implementation.

The tests are intentionally honest about scope: they verify the TypeScript protocol simulator and Aztec/Noir-inspired stubs, **not** a live Aztec chain deployment.

## Trade object model

### Public header fields

- `objectId`
- `schemaId`
- `version`
- `parentVersionHash`
- `lifecycleState`
- `stakeholderRoot`
- `policyHash`
- `fieldRoot`
- `complianceRoot`
- `revocationEpoch`
- `settlementRef`
- `settlementStatus`
- optional `productType`
- optional `notionalBucket`

### Private fields

- `x`
- `y`
- `z`
- `pricingDetails`
- `counterpartyMetadata`
- `internalRiskNotes`

## Visibility bundles

Policy is **bundle-first**, not raw per-field ACL sprawl:

- `fullTradeCore` → `x`, `y`, `z`
- `counterpartyCore` → `x`, `y`
- `observerCore` → `y`
- `regulatorInquiry` → `x`, `z` with lawful-basis metadata and receipt recording
- `pricingSupplement` → `pricingDetails`
- `counterpartySupplement` → `counterpartyMetadata`
- `internalRiskSupplement` → `internalRiskNotes`

Mapped roles in the default policy:

- **A** sees `x,y,z`
- **B** sees `x,y`
- **C** sees `y`
- **R** sees `x,z` under policy `P` / lawful basis

## Lifecycle

- `Draft`
- `Proposed`
- `Matched`
- `Approved`
- `Settled`
- `Closed`
- `Cancelled`

## Public events covered

The simulator emits public events analogous to:

- `ObjectCreated`
- `ObjectVersioned`
- `LifecycleTransitioned`
- `PolicyAttached`
- `StakeholderSetUpdated`
- `DisclosureRecorded`
- `ComplianceProofRecorded`
- `SettlementBound`
- `SettlementCompleted`
- `RevocationEpochAdvanced`
- `ObjectCancelled`

## Repo structure

- `docs/architecture.md` — protocol overview and plane split
- `schemas/trade.schema.json` — trade object schema
- `policies/policy.trade.json` — shared policy DSL/config
- `src/aztec/TradeKernel.nr` — Noir-inspired note/disclosure kernel sketch
- `src/aztec/PublicCoordination.contract.ts` — Aztec app contract design sketch
- `src/types.ts` — core model types
- `src/protocol.ts` — working simulator for protocol state transitions
- `src/demo.ts` — end-to-end demo script
- `test/protocol.test.ts` — automated simulator tests
- `scripts/run-demo.sh` — one-command demo runner

## Quickstart

```bash
npm install
npm test
npm run demo
```

Or:

```bash
./scripts/run-demo.sh
```

## Demo flow included

The demo covers:

1. institution registration for `A`, `B`, `C`, `R`
2. policy attachment
3. trade creation in `Draft`
4. lifecycle transition to `Proposed`
5. versioning update to v2
6. lifecycle transitions through `Matched`, `Approved`, `Settled`, `Closed`
7. regulator disclosure package request/receipt with lawful-basis metadata
8. proof-only compliance assertion recorded publicly
9. settlement binding and settlement completion
10. revocation epoch advancement

## Automated test coverage

The automated tests cover the simulator’s public/protocol behavior, including:

1. institution registration and emitted public events
2. trade creation defaults and policy attachment receipt
3. trade versioning and parent version hash updates
4. lifecycle progression rules, including backward/terminal rejection
5. regulator disclosure receipt creation and bundle scoping
6. compliance proof receipt recording and compliance root updates
7. settlement binding/progression and final settlement completion
8. revocation epoch advancement
9. cancellation event emission

## MVP scope choices

Included:

- coherent public/private/disclosure split
- selective disclosure bundles
- public receipts for regulator access
- proof-only compliance receipt
- internal settlement progression
- runnable simulator tests for the TypeScript model

Explicitly out of scope:

- L1/Base integration
- large document storage (only a stub hook is modeled)
- full Aztec deployment plumbing
- production cryptography
- any claim that this repo deploys a real Aztec app in this environment

## Next step to productionize

Replace the simulator methods with real Aztec app contract calls and Noir circuits while preserving:

- public header/event surface
- private note bundles
- disclosure receipt format
- compliance proof commitment outputs
