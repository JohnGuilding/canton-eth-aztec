# Canton-style Multiparty Trade Protocol on Aztec

A real Noir/Aztec smart contract implementing Canton Network-style multiparty trade lifecycle with native privacy. Trade objects are split across three planes: public coordination headers visible to all, encrypted private notes with per-stakeholder field visibility, and a regulated disclosure layer with cryptographic receipts.

Built on Aztec Network (v4.0.0-devnet.2-patch.1) using aztec-nr for private state, encrypted notes, and nullifier-based versioning.

### Development status

**What was built:**
- A compiling Noir smart contract (`TradeProtocol`) with 18 entrypoints covering institution registration, trade creation with selective disclosure, lifecycle state machine (7 states), trade versioning, regulator disclosure with receipt notes, in-circuit compliance proofs, settlement management, revocation epochs, and cancellation.
- Two custom note types: `TradeNote` (8 fields, per-stakeholder visibility) and `DisclosureNote` (7 fields, bilateral receipts).
- Policy configuration (`policy.trade.json`) defining 7 bundle classes and 4 role bindings.
- JSON Schema for trade object validation.

**What is missing:**
- TypeScript SDK wrapping the contract calls (planned in `src/sdk/`).
- Deploy script and integration tests against a local Aztec network.
- Generated TypeScript bindings (`aztec codegen` step).
- Old simulator files (`src/protocol.ts`, `src/demo.ts`, etc.) have not been removed yet.
- No L1/Ethereum settlement integration.

## Project structure

```
contracts/trade_protocol/       Noir smart contract (aztec-nr)
  src/main.nr                   Core contract (18 functions)
  src/trade_note.nr             Custom encrypted note for trade data
  src/disclosure_note.nr        Custom encrypted note for disclosure receipts
  src/types.nr                  TradeHeader struct, lifecycle/settlement constants
policies/policy.trade.json      Selective disclosure policy (bundle classes + role bindings)
schemas/trade.schema.json       JSON Schema for trade objects
docs/architecture.md            Protocol architecture overview
target/                         Compiled contract output (generated)
src/artifacts/                  TypeScript bindings (generated, not yet created)
src/sdk/                        TypeScript SDK (planned, not yet created)
```

### Prerequisites

```bash
# Install Aztec toolchain
VERSION=4.0.0-devnet.2-patch.1 bash -i <(curl -sL https://install.aztec.network/4.0.0-devnet.2-patch.1)
aztec-up use 4.0.0-devnet.2-patch.1

# PATH must include:
#   ~/.aztec/current/bin
#   ~/.aztec/current/node_modules/.bin
```

### Build

```bash
aztec compile                    # Compile Noir contract + transpile + generate VKs
aztec codegen target --outdir src/artifacts   # Generate TypeScript bindings (requires compile first)
```

### Test

```bash
aztec test                       # Run Noir unit tests (if any)
# Integration tests (planned): npm run test:integration
```

## How it works

The contract implements a three-plane architecture inspired by the Canton Network's privacy model, built entirely on Aztec's native privacy primitives.

**Public coordination plane** -- All participants share a `TradeHeader` stored in public contract state. This contains the object ID, schema, version, lifecycle state, stakeholder root, policy hash, field root, compliance root, settlement status, and revocation epoch. Anyone can read this; it provides a common timeline without revealing confidential trade terms.

**Private data plane** -- Confidential trade fields (`x`, `y`, `z`) are stored as encrypted `TradeNote`s in Aztec's private note hash tree. Each stakeholder receives a note with visibility determined by their policy bundle:

| Role | Bundle | Sees |
|------|--------|------|
| A (originator) | fullTradeCore | x, y, z |
| B (counterparty) | counterpartyCore | x, y |
| C (observer) | observerCore | y |
| R (regulator) | regulatorInquiry | x, y (only via explicit disclosure) |

Notes are encrypted with the owner's public key. Only that stakeholder's PXE can decrypt them. Fields set to `0` in a note indicate "not visible to this stakeholder."

**Disclosure/proof plane** -- Regulated disclosure creates a `TradeNote` for the regulator containing the authorized field subset, plus bilateral `DisclosureNote` receipts for both the discloser and regulator. Compliance proofs assert conditions (e.g., exposure within desk limit) in-circuit without revealing the underlying private values, then update a public compliance root.

**Technology:** Noir (circuit language), aztec-nr (contract framework), Aztec Network (privacy-preserving L2), UTXO-style private notes with nullifiers, private-to-public enqueue pattern for cross-plane calls.

## Comparison to Canton Network

### What this replicates from Canton

- **Multiparty privacy with selective visibility** -- Each stakeholder sees only what policy permits, enforced cryptographically rather than by access control lists.
- **Public coordination with private data** -- Shared headers and lifecycle state visible to all; confidential terms visible only to authorized parties.
- **Policy-driven disclosure bundles** -- Visibility is defined by bundle classes in a policy file, not ad-hoc per-field permissions.
- **Regulated disclosure with receipts** -- Regulator access requires explicit disclosure with lawful basis metadata. Both parties receive cryptographic receipts.
- **Versioning with nullification** -- New trade versions nullify old private notes and re-issue updated ones, analogous to Canton's versioned contract model.
- **Lifecycle state machine** -- 7-state forward-only progression (Draft, Proposed, Matched, Approved, Settled, Closed) with cancellation from any non-terminal state.
- **Compliance proofs** -- Proof-only assertions that update a public root without revealing private inputs.

### What Canton has that this does not

- **Sub-transaction privacy** -- Canton's sub-transactions let different participants see different parts of a single atomic transaction. Aztec's model is note-level, not sub-transaction-level.
- **Daml smart contract language** -- Canton uses Daml for contract modeling with built-in authorization and privacy semantics. This uses Noir, which is lower-level.
- **Participant-level topology** -- Canton has a full participant/domain/mediator topology. This contract has a flat institution registry.
- **Conflict detection and resolution** -- Canton's domain-level conflict detection. This contract uses simpler public state assertions.
- **Cross-domain transactions** -- Canton supports multi-domain atomic transactions. This is single-contract.
- **Production identity and key management** -- Canton has full PKI infrastructure. This relies on Aztec address-based identity.

### What Ethereum/Aztec provides that Canton does not

- **Permissionless deployment** -- Anyone can deploy and interact; no consortium setup required.
- **Programmable settlement on L1** -- Direct path to Ethereum L1 settlement, DeFi composability, and token integration.
- **Cryptographic privacy enforcement** -- Privacy is enforced by zero-knowledge proofs and encryption, not by trusting participant nodes to withhold data.
- **Public verifiability** -- Anyone can verify state transitions and proofs without being a network participant.
- **Censorship resistance** -- No single operator can block transactions (Aztec inherits Ethereum's properties).
- **Open-source toolchain** -- Noir, aztec-nr, and the Aztec network are open source.

## Privacy model

### What is public (visible to everyone)

- `TradeHeader`: object ID, schema ID, version number, parent version hash, lifecycle state, stakeholder root (hash of stakeholder set), policy hash, field root (hash of private fields), compliance root, revocation epoch, settlement reference, settlement status, creator address.
- Lifecycle state transitions and their ordering.
- That a disclosure occurred (via the enqueued `_record_disclosure_receipt` call), but not what was disclosed.
- That a compliance proof was recorded, and the resulting compliance root, but not the private inputs.
- Settlement binding and progression events.
- Institution registration (ID, role, address).

### What is private (visible only to authorized stakeholders)

- Trade field values (`x`, `y`, `z`) -- each stakeholder sees only the subset their bundle permits.
- The `payload_hash` linking to extended off-chain data.
- Which specific fields were disclosed to the regulator (only the discloser and regulator know).
- The private inputs to compliance proofs (e.g., actual exposure values used to prove within-limit).
- The link between a stakeholder's identity and their specific note contents (notes are encrypted per-owner).

### How privacy is enforced

- **Encryption**: Notes are encrypted with the owner's public key and stored in Aztec's private note hash tree. Only the owner's PXE (Private eXecution Environment) can decrypt them.
- **Nullifiers**: When a trade is versioned, old notes are nullified (consumed) and new notes are created. The nullifier prevents double-use without revealing which note was consumed.
- **Private-to-public enqueue**: Private functions compute over encrypted data locally, then enqueue public state updates that contain only commitments/roots, not raw values.
- **In-circuit assertions**: Compliance proofs run inside the circuit -- the prover demonstrates a condition holds without revealing the values.

## Known design faults

1. **No in-circuit hash verification for field_root** -- The `field_root` is passed as a parameter to `create_trade` rather than computed from `x, y, z` inside the circuit. A malicious caller could pass an inconsistent root. Production should compute `poseidon2(x, y, z)` in-circuit.

2. **Simple sum for receipt_id** -- The disclosure `receipt_id` is computed as `x + y + lawful_basis_hash + request_ref + object_id` (field addition). This is not collision-resistant. Production should use Poseidon2 hashing.

3. **No range proof for compliance** -- The `exposureWithinDeskLimit` check uses `assert(exposure != desk_limit)` which only proves non-equality, not less-than. Field arithmetic does not support ordering comparisons. Production would need to cast to bounded integers or use range proof gadgets.

4. **get_notes nullifies** -- Reading a trade note for disclosure or compliance proof requires nullifying and re-creating it. This changes the note's nullifier, creating a timing correlation: an observer can see that _something_ happened to a note at a specific time, even if they can't see what.

5. **No stakeholder authorization on lifecycle transitions** -- `transition_lifecycle` does not check that the caller is an authorized stakeholder. Any address can advance the lifecycle. Production should verify the caller against the stakeholder root or institution registry.

6. **Flat institution model** -- Institutions are registered by a single admin with a simple role enum. No delegation, no multi-sig, no hierarchical authorization.

7. **No event emission** -- The contract updates public state but does not emit Aztec events. Clients must poll state rather than subscribe to changes.

8. **Settlement is not wired to L1** -- Settlement status is tracked internally but not connected to any actual settlement mechanism on Ethereum L1.

9. **Single-note-per-stakeholder assumption** -- `get_notes` returns all notes and the code takes `notes.get(0)`. If a stakeholder has multiple notes for the same `object_id` (e.g., from multiple versions), only the first is processed.

10. **Cancel stores reason_hash in settlement_ref** -- Cancellation overwrites the `settlement_ref` field with the reason hash, which loses any previously bound settlement reference.
