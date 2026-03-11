# Architecture

## Goal

Prototype an **Aztec-only** analogue to a Canton-style multiparty object protocol where:

- public coordination is shared and auditable
- confidential fields live in private state
- disclosure is selective, policy-bound, and receipt-bearing

## Three planes

### 1) Public coordination plane

Stored as public state or public event commitments:

- trade header
- lifecycle state
- stakeholder root
- policy hash
- field root
- compliance root
- revocation epoch
- settlement reference + public settlement status
- disclosure receipt metadata

This plane gives all participants a common object timeline without revealing the private payload.

### 2) Private data plane

Modeled using Aztec-native concepts:

- private notes for confidential bundles
- note ownership keyed to institutions or role bundles
- nullifier-style consumption on versioning
- private commitments for field groups rather than fully public field storage

Private fields in this prototype:

- `x`
- `y`
- `z`
- `pricingDetails`
- `counterpartyMetadata`
- `internalRiskNotes`

### 3) Disclosure / proof plane

Selective disclosure and proof receipts are separated from baseline ownership:

- disclosure package references point to a policy-authorized reveal bundle
- regulator access records include lawful basis and recipient metadata
- compliance proofs can update a public compliance root without exposing underlying private inputs

## Object anatomy

### Public header

The public header is the canonical coordination envelope:

```text
objectId
schemaId
version
parentVersionHash
lifecycleState
stakeholderRoot
policyHash
fieldRoot
complianceRoot
revocationEpoch
settlementRef
settlementStatus
productType?
notionalBucket?
```

### Private content

Private content is grouped into bundles rather than independently managed fields.

## Policy model

The policy file uses bundle classes:

- `fullTradeCore`
- `counterpartyCore`
- `observerCore`
- `regulatorInquiry`
- `pricingSupplement`
- `counterpartySupplement`
- `internalRiskSupplement`

This keeps the selective disclosure surface compact and auditable.

## Institutions

The demo registers four institutions:

- `A` — full trade participant
- `B` — counterparty participant
- `C` — limited observer
- `R` — regulator

## Versioning model

Each new trade version:

- increments `version`
- references `parentVersionHash`
- derives a fresh `fieldRoot`
- can advance lifecycle and settlement state
- conceptually nullifies prior private notes and reissues updated notes

## Disclosure model

A disclosure event records:

- object id + version
- recipient institution
- bundle id(s)
- lawful basis metadata
- policy reference/hash
- disclosure package commitment/receipt id

The private payload itself stays off the public surface.

## Compliance model

The prototype includes a proof-only assertion:

- `exposureWithinDeskLimit`

Publicly recorded:

- proof type
- proof commitment/hash
- resulting compliance root update

Privately used inputs may include `x`, `z`, pricing values, or risk metadata, but none are exposed publicly.

## Settlement model

Settlement is deliberately internal to the object graph:

- bind a `settlementRef`
- move status from `Pending` to `InFlight` to `Final`
- emit binding and completion receipts publicly

No L1 or Base integration is attempted.

## Implementation split in this repo

### Runnable today

- TypeScript simulator that models all flows and prints event logs

### Aztec-oriented design stubs

- Noir-style kernel sketch for private note handling and selective disclosure
- public contract sketch documenting expected public entrypoints and events

This makes the repo useful immediately while still being structurally honest about the intended target stack.
