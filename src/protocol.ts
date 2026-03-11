import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import type {
  Institution,
  InstitutionId,
  LifecycleState,
  PublicEvent,
  SettlementStatus,
  TradeObject,
  TradePolicy,
  TradePrivatePayload,
  TradePublicHeader,
} from './types.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const policy = JSON.parse(
  readFileSync(join(__dirname, '..', 'policies', 'policy.trade.json'), 'utf8'),
) as TradePolicy;

const lifecycleOrder: LifecycleState[] = [
  'Draft',
  'Proposed',
  'Matched',
  'Approved',
  'Settled',
  'Closed',
  'Cancelled',
];

function hash(input: unknown): string {
  return createHash('sha256').update(JSON.stringify(input)).digest('hex');
}

function now(): string {
  return new Date().toISOString();
}

function pickFields(payload: TradePrivatePayload, fields: string[]) {
  return Object.fromEntries(fields.map((f) => [f, payload[f as keyof TradePrivatePayload]]));
}

export class TradeProtocol {
  readonly institutions = new Map<InstitutionId, Institution>();
  readonly events: PublicEvent[] = [];
  trade?: TradeObject;

  private emit(name: PublicEvent['name'], data: Record<string, unknown>) {
    this.events.push({ at: now(), name, data });
  }

  registerInstitution(institution: Institution) {
    this.institutions.set(institution.id, institution);
    this.emit('InstitutionRegistered', { ...institution });
  }

  attachPolicy(objectId: string) {
    this.emit('PolicyAttached', {
      objectId,
      policyId: policy.policyId,
      policyHash: hash(policy),
      bundleClasses: Object.keys(policy.bundleClasses),
    });
  }

  private stakeholderRoot(stakeholders: InstitutionId[]) {
    return hash(stakeholders.slice().sort());
  }

  private fieldRoot(payload: TradePrivatePayload) {
    return hash({
      core: pickFields(payload, ['x', 'y', 'z']),
      pricing: payload.pricingDetails,
      counterparty: payload.counterpartyMetadata,
      risk: payload.internalRiskNotes,
    });
  }

  private complianceRoot(assertions: unknown[] = []) {
    return hash(assertions);
  }

  createTrade(args: {
    objectId: string;
    stakeholders: InstitutionId[];
    payload: TradePrivatePayload;
    productType?: string;
    notionalBucket?: string;
  }) {
    const header: TradePublicHeader = {
      objectId: args.objectId,
      schemaId: 'trade.schema.json',
      version: 1,
      parentVersionHash: 'GENESIS',
      lifecycleState: 'Draft',
      stakeholderRoot: this.stakeholderRoot(args.stakeholders),
      policyHash: hash(policy),
      fieldRoot: this.fieldRoot(args.payload),
      complianceRoot: this.complianceRoot(),
      revocationEpoch: 0,
      settlementRef: null,
      settlementStatus: 'Unbound',
      productType: args.productType ?? null,
      notionalBucket: args.notionalBucket ?? null,
    };

    this.trade = { publicHeader: header, privatePayload: args.payload };

    this.emit('StakeholderSetUpdated', {
      objectId: header.objectId,
      version: header.version,
      stakeholders: args.stakeholders,
      stakeholderRoot: header.stakeholderRoot,
    });

    this.emit('ObjectCreated', {
      ...header,
    });

    return this.trade;
  }

  versionTrade(updatedPayload: TradePrivatePayload) {
    if (!this.trade) throw new Error('trade not initialized');
    const prev = this.trade.publicHeader;
    const nextHeader: TradePublicHeader = {
      ...prev,
      version: prev.version + 1,
      parentVersionHash: hash(prev),
      fieldRoot: this.fieldRoot(updatedPayload),
    };
    this.trade = { publicHeader: nextHeader, privatePayload: updatedPayload };
    this.emit('ObjectVersioned', {
      objectId: nextHeader.objectId,
      version: nextHeader.version,
      parentVersionHash: nextHeader.parentVersionHash,
      fieldRoot: nextHeader.fieldRoot,
    });
  }

  transitionLifecycle(nextState: LifecycleState) {
    if (!this.trade) throw new Error('trade not initialized');
    const current = this.trade.publicHeader.lifecycleState;
    if (current === 'Cancelled' || current === 'Closed') {
      throw new Error(`terminal lifecycle state: ${current}`);
    }
    const currentIndex = lifecycleOrder.indexOf(current);
    const nextIndex = lifecycleOrder.indexOf(nextState);
    if (nextState !== 'Cancelled' && nextIndex < currentIndex) {
      throw new Error(`cannot move lifecycle backward: ${current} -> ${nextState}`);
    }
    this.trade.publicHeader.lifecycleState = nextState;
    this.emit('LifecycleTransitioned', {
      objectId: this.trade.publicHeader.objectId,
      version: this.trade.publicHeader.version,
      from: current,
      to: nextState,
    });
  }

  bindSettlement(settlementRef: string) {
    if (!this.trade) throw new Error('trade not initialized');
    this.trade.publicHeader.settlementRef = settlementRef;
    this.trade.publicHeader.settlementStatus = 'Pending';
    this.emit('SettlementBound', {
      objectId: this.trade.publicHeader.objectId,
      version: this.trade.publicHeader.version,
      settlementRef,
      settlementStatus: 'Pending',
    });
  }

  progressSettlement(status: SettlementStatus) {
    if (!this.trade) throw new Error('trade not initialized');
    this.trade.publicHeader.settlementStatus = status;
    if (status === 'Final') {
      this.emit('SettlementCompleted', {
        objectId: this.trade.publicHeader.objectId,
        version: this.trade.publicHeader.version,
        settlementRef: this.trade.publicHeader.settlementRef,
        settlementStatus: status,
      });
      return;
    }
    this.emit('LifecycleTransitioned', {
      objectId: this.trade.publicHeader.objectId,
      version: this.trade.publicHeader.version,
      from: 'SettlementProgress',
      to: status,
    });
  }

  discloseToRegulator(args: {
    lawfulBasis: string;
    requestRef: string;
    recipient: InstitutionId;
  }) {
    if (!this.trade) throw new Error('trade not initialized');
    const bundles = policy.roleBindings[args.recipient];
    if (!bundles?.includes('regulatorInquiry')) {
      throw new Error(`recipient ${args.recipient} lacks regulatorInquiry bundle`);
    }
    const fields = policy.bundleClasses.regulatorInquiry.fields;
    const disclosed = pickFields(this.trade.privatePayload, fields);
    const receiptId = hash({ objectId: this.trade.publicHeader.objectId, lawfulBasis: args.lawfulBasis, disclosed, requestRef: args.requestRef });
    this.emit('DisclosureRecorded', {
      objectId: this.trade.publicHeader.objectId,
      version: this.trade.publicHeader.version,
      recipient: args.recipient,
      bundles: ['regulatorInquiry'],
      lawfulBasis: args.lawfulBasis,
      requestRef: args.requestRef,
      receiptId,
      policyId: policy.policyId,
      policyHash: this.trade.publicHeader.policyHash,
    });
    return { disclosed, receiptId };
  }

  recordComplianceProof(args: {
    proofType: 'exposureWithinDeskLimit';
    publicInputs: Record<string, unknown>;
  }) {
    if (!this.trade) throw new Error('trade not initialized');
    const proofCommitment = hash(args);
    const nextComplianceRoot = this.complianceRoot([this.trade.publicHeader.complianceRoot, proofCommitment]);
    this.trade.publicHeader.complianceRoot = nextComplianceRoot;
    this.emit('ComplianceProofRecorded', {
      objectId: this.trade.publicHeader.objectId,
      version: this.trade.publicHeader.version,
      proofType: args.proofType,
      proofCommitment,
      complianceRoot: nextComplianceRoot,
      publicInputs: args.publicInputs,
    });
  }

  advanceRevocationEpoch(reason: string) {
    if (!this.trade) throw new Error('trade not initialized');
    this.trade.publicHeader.revocationEpoch += 1;
    this.emit('RevocationEpochAdvanced', {
      objectId: this.trade.publicHeader.objectId,
      version: this.trade.publicHeader.version,
      revocationEpoch: this.trade.publicHeader.revocationEpoch,
      reason,
    });
  }

  cancel(reason: string) {
    if (!this.trade) throw new Error('trade not initialized');
    this.trade.publicHeader.lifecycleState = 'Cancelled';
    this.emit('ObjectCancelled', {
      objectId: this.trade.publicHeader.objectId,
      version: this.trade.publicHeader.version,
      reason,
    });
  }

  snapshot() {
    if (!this.trade) throw new Error('trade not initialized');
    return structuredClone(this.trade);
  }
}

export { policy, hash };
