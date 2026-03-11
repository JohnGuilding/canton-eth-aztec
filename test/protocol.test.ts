import test from 'node:test';
import assert from 'node:assert/strict';

import { TradeProtocol, hash, policy } from '../src/protocol.js';
import type { Institution, TradePrivatePayload } from '../src/types.js';

const institutions: Institution[] = [
  { id: 'A', name: 'Institution A', role: 'Originator', publicKey: 'aztec-pk-a' },
  { id: 'B', name: 'Institution B', role: 'Counterparty', publicKey: 'aztec-pk-b' },
  { id: 'C', name: 'Institution C', role: 'Observer', publicKey: 'aztec-pk-c' },
  { id: 'R', name: 'Regulator R', role: 'Regulator', publicKey: 'aztec-pk-r' },
];

function makePayload(overrides: Partial<TradePrivatePayload> = {}): TradePrivatePayload {
  return {
    x: 'fixedRate=4.15%',
    y: 'notional=25m',
    z: 'tenor=5Y',
    pricingDetails: { mtmModel: 'curve-v1', premiumBps: 12 },
    counterpartyMetadata: { leiA: 'A-LEI-001', leiB: 'B-LEI-002' },
    internalRiskNotes: { desk: 'Rates-EMEA', limitBucket: 'IR-5Y', analyst: 'risk.bot' },
    ...overrides,
  };
}

function setupProtocol() {
  const protocol = new TradeProtocol();
  for (const institution of institutions) {
    protocol.registerInstitution(institution);
  }
  return protocol;
}

test('registers institutions and emits public registration events', () => {
  const protocol = setupProtocol();

  assert.equal(protocol.institutions.size, 4);
  assert.deepEqual([...protocol.institutions.keys()], ['A', 'B', 'C', 'R']);
  assert.equal(protocol.events.length, 4);
  assert.deepEqual(
    protocol.events.map((event) => event.name),
    ['InstitutionRegistered', 'InstitutionRegistered', 'InstitutionRegistered', 'InstitutionRegistered'],
  );
  assert.equal(protocol.events[0]?.data.id, 'A');
  assert.equal(protocol.events[3]?.data.id, 'R');
});

test('creates a trade with expected public header defaults and policy attachment event', () => {
  const protocol = setupProtocol();
  const payload = makePayload();

  protocol.attachPolicy('TRD-001');
  const trade = protocol.createTrade({
    objectId: 'TRD-001',
    stakeholders: ['A', 'B', 'C', 'R'],
    payload,
    productType: 'InterestRateSwap',
    notionalBucket: '10m-50m',
  });

  assert.equal(trade.publicHeader.objectId, 'TRD-001');
  assert.equal(trade.publicHeader.version, 1);
  assert.equal(trade.publicHeader.parentVersionHash, 'GENESIS');
  assert.equal(trade.publicHeader.lifecycleState, 'Draft');
  assert.equal(trade.publicHeader.policyHash, hash(policy));
  assert.equal(trade.publicHeader.settlementStatus, 'Unbound');
  assert.equal(trade.publicHeader.settlementRef, null);
  assert.equal(trade.publicHeader.revocationEpoch, 0);
  assert.equal(trade.publicHeader.productType, 'InterestRateSwap');
  assert.equal(trade.publicHeader.notionalBucket, '10m-50m');

  const eventNames = protocol.events.map((event) => event.name);
  assert.deepEqual(eventNames.slice(-3), ['PolicyAttached', 'StakeholderSetUpdated', 'ObjectCreated']);
  assert.equal(protocol.events.at(-1)?.data.objectId, 'TRD-001');
});

test('versions a trade and records parent version hash plus new field root', () => {
  const protocol = setupProtocol();
  const payloadV1 = makePayload();

  protocol.createTrade({
    objectId: 'TRD-001',
    stakeholders: ['A', 'B', 'C', 'R'],
    payload: payloadV1,
  });

  const beforeVersion = protocol.snapshot().publicHeader;
  const payloadV2 = makePayload({
    y: 'notional=30m',
    pricingDetails: { mtmModel: 'curve-v2', premiumBps: 10 },
  });

  protocol.versionTrade(payloadV2);
  const afterVersion = protocol.snapshot();
  const versionEvent = protocol.events.at(-1);

  assert.equal(afterVersion.publicHeader.version, 2);
  assert.equal(afterVersion.publicHeader.parentVersionHash, hash(beforeVersion));
  assert.notEqual(afterVersion.publicHeader.fieldRoot, beforeVersion.fieldRoot);
  assert.deepEqual(afterVersion.privatePayload, payloadV2);
  assert.equal(versionEvent?.name, 'ObjectVersioned');
  assert.equal(versionEvent?.data.version, 2);
});

test('supports forward lifecycle transitions and rejects backward or terminal transitions', () => {
  const protocol = setupProtocol();

  protocol.createTrade({
    objectId: 'TRD-001',
    stakeholders: ['A', 'B', 'C', 'R'],
    payload: makePayload(),
  });

  protocol.transitionLifecycle('Proposed');
  protocol.transitionLifecycle('Matched');
  protocol.transitionLifecycle('Approved');

  assert.equal(protocol.snapshot().publicHeader.lifecycleState, 'Approved');
  assert.throws(() => protocol.transitionLifecycle('Draft'), /cannot move lifecycle backward/);

  protocol.transitionLifecycle('Settled');
  protocol.transitionLifecycle('Closed');

  assert.equal(protocol.snapshot().publicHeader.lifecycleState, 'Closed');
  assert.throws(() => protocol.transitionLifecycle('Cancelled'), /terminal lifecycle state: Closed/);
});

test('creates regulator disclosure receipts with only the configured regulator bundle fields', () => {
  const protocol = setupProtocol();
  const payload = makePayload();

  protocol.createTrade({
    objectId: 'TRD-001',
    stakeholders: ['A', 'B', 'C', 'R'],
    payload,
  });

  const receipt = protocol.discloseToRegulator({
    recipient: 'R',
    lawfulBasis: 'MiFID II Article 25 supervisory request',
    requestRef: 'REQ-R-2026-03-10-01',
  });

  assert.deepEqual(receipt.disclosed, {
    x: payload.x,
    z: payload.z,
  });
  assert.ok(receipt.receiptId.length > 0);

  const event = protocol.events.at(-1);
  assert.equal(event?.name, 'DisclosureRecorded');
  assert.equal(event?.data.recipient, 'R');
  assert.deepEqual(event?.data.bundles, ['regulatorInquiry']);
  assert.equal(event?.data.policyId, policy.policyId);

  assert.throws(
    () =>
      protocol.discloseToRegulator({
        recipient: 'C',
        lawfulBasis: 'test',
        requestRef: 'REQ-FAIL-01',
      }),
    /lacks regulatorInquiry bundle/,
  );
});

test('records a proof-only compliance receipt and advances the compliance root', () => {
  const protocol = setupProtocol();

  protocol.createTrade({
    objectId: 'TRD-001',
    stakeholders: ['A', 'B', 'C', 'R'],
    payload: makePayload(),
  });

  const before = protocol.snapshot().publicHeader.complianceRoot;
  protocol.recordComplianceProof({
    proofType: 'exposureWithinDeskLimit',
    publicInputs: {
      desk: 'Rates-EMEA',
      limitBucket: 'IR-5Y',
      assertion: 'desk exposure under approved threshold',
    },
  });

  const after = protocol.snapshot().publicHeader.complianceRoot;
  const event = protocol.events.at(-1);

  assert.notEqual(after, before);
  assert.equal(event?.name, 'ComplianceProofRecorded');
  assert.equal(event?.data.proofType, 'exposureWithinDeskLimit');
  assert.equal(event?.data.complianceRoot, after);
  assert.ok(typeof event?.data.proofCommitment === 'string');
});

test('tracks settlement binding/progression and revocation epoch advancement', () => {
  const protocol = setupProtocol();

  protocol.createTrade({
    objectId: 'TRD-001',
    stakeholders: ['A', 'B', 'C', 'R'],
    payload: makePayload(),
  });

  protocol.bindSettlement('SETTLE-INT-001');
  assert.equal(protocol.snapshot().publicHeader.settlementRef, 'SETTLE-INT-001');
  assert.equal(protocol.snapshot().publicHeader.settlementStatus, 'Pending');
  assert.equal(protocol.events.at(-1)?.name, 'SettlementBound');

  protocol.progressSettlement('InFlight');
  assert.equal(protocol.snapshot().publicHeader.settlementStatus, 'InFlight');
  assert.equal(protocol.events.at(-1)?.name, 'LifecycleTransitioned');
  assert.equal(protocol.events.at(-1)?.data.to, 'InFlight');

  protocol.progressSettlement('Final');
  assert.equal(protocol.snapshot().publicHeader.settlementStatus, 'Final');
  assert.equal(protocol.events.at(-1)?.name, 'SettlementCompleted');

  protocol.advanceRevocationEpoch('superseded regulator disclosure package baseline');
  assert.equal(protocol.snapshot().publicHeader.revocationEpoch, 1);
  assert.equal(protocol.events.at(-1)?.name, 'RevocationEpochAdvanced');
  assert.equal(protocol.events.at(-1)?.data.reason, 'superseded regulator disclosure package baseline');
});

test('cancels a trade and emits an ObjectCancelled event', () => {
  const protocol = setupProtocol();

  protocol.createTrade({
    objectId: 'TRD-001',
    stakeholders: ['A', 'B', 'C', 'R'],
    payload: makePayload(),
  });

  protocol.cancel('trade rejected before matching');

  assert.equal(protocol.snapshot().publicHeader.lifecycleState, 'Cancelled');
  assert.equal(protocol.events.at(-1)?.name, 'ObjectCancelled');
  assert.equal(protocol.events.at(-1)?.data.reason, 'trade rejected before matching');
});
