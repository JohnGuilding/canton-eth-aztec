import { TradeProtocol } from './protocol.js';
import type { Institution, TradePrivatePayload } from './types.js';

function printSection(title: string) {
  console.log(`\n=== ${title} ===`);
}

const protocol = new TradeProtocol();

const institutions: Institution[] = [
  { id: 'A', name: 'Institution A', role: 'Originator', publicKey: 'aztec-pk-a' },
  { id: 'B', name: 'Institution B', role: 'Counterparty', publicKey: 'aztec-pk-b' },
  { id: 'C', name: 'Institution C', role: 'Observer', publicKey: 'aztec-pk-c' },
  { id: 'R', name: 'Regulator R', role: 'Regulator', publicKey: 'aztec-pk-r' },
];

printSection('Institution registration');
for (const institution of institutions) {
  protocol.registerInstitution(institution);
  console.log(`registered ${institution.id} (${institution.role})`);
}

const payloadV1: TradePrivatePayload = {
  x: 'fixedRate=4.15%',
  y: 'notional=25m',
  z: 'tenor=5Y',
  pricingDetails: { mtmModel: 'curve-v1', premiumBps: 12 },
  counterpartyMetadata: { leiA: 'A-LEI-001', leiB: 'B-LEI-002' },
  internalRiskNotes: { desk: 'Rates-EMEA', limitBucket: 'IR-5Y', analyst: 'risk.bot' },
};

printSection('Trade creation');
protocol.attachPolicy('TRD-001');
protocol.createTrade({
  objectId: 'TRD-001',
  stakeholders: ['A', 'B', 'C', 'R'],
  payload: payloadV1,
  productType: 'InterestRateSwap',
  notionalBucket: '10m-50m',
});
console.log(protocol.snapshot().publicHeader);

printSection('Lifecycle to Proposed');
protocol.transitionLifecycle('Proposed');

const payloadV2: TradePrivatePayload = {
  ...payloadV1,
  y: 'notional=30m',
  pricingDetails: { mtmModel: 'curve-v2', premiumBps: 10 },
};

printSection('Object versioning');
protocol.versionTrade(payloadV2);
console.log(protocol.snapshot().publicHeader);

printSection('Lifecycle progression');
protocol.transitionLifecycle('Matched');
protocol.transitionLifecycle('Approved');

printSection('Proof-only compliance assertion');
protocol.recordComplianceProof({
  proofType: 'exposureWithinDeskLimit',
  publicInputs: {
    desk: 'Rates-EMEA',
    limitBucket: 'IR-5Y',
    assertion: 'desk exposure under approved threshold',
  },
});

printSection('Regulator disclosure package + public receipt');
const disclosure = protocol.discloseToRegulator({
  recipient: 'R',
  lawfulBasis: 'MiFID II Article 25 supervisory request',
  requestRef: 'REQ-R-2026-03-10-01',
});
console.log(disclosure);

printSection('Settlement progression');
protocol.bindSettlement('SETTLE-INT-001');
protocol.progressSettlement('InFlight');
protocol.progressSettlement('Final');
protocol.transitionLifecycle('Settled');
protocol.advanceRevocationEpoch('superseded regulator disclosure package baseline');
protocol.transitionLifecycle('Closed');

printSection('Final public header');
console.log(protocol.snapshot().publicHeader);

printSection('Public event log');
for (const event of protocol.events) {
  console.log(JSON.stringify(event, null, 2));
}
