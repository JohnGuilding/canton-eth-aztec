export type InstitutionId = 'A' | 'B' | 'C' | 'R';

export type LifecycleState =
  | 'Draft'
  | 'Proposed'
  | 'Matched'
  | 'Approved'
  | 'Settled'
  | 'Closed'
  | 'Cancelled';

export type SettlementStatus = 'Unbound' | 'Pending' | 'InFlight' | 'Final';

export interface Institution {
  id: InstitutionId;
  name: string;
  role: 'Originator' | 'Counterparty' | 'Observer' | 'Regulator';
  publicKey: string;
}

export interface TradePublicHeader {
  objectId: string;
  schemaId: string;
  version: number;
  parentVersionHash: string;
  lifecycleState: LifecycleState;
  stakeholderRoot: string;
  policyHash: string;
  fieldRoot: string;
  complianceRoot: string;
  revocationEpoch: number;
  settlementRef: string | null;
  settlementStatus: SettlementStatus;
  productType?: string | null;
  notionalBucket?: string | null;
}

export interface TradePrivatePayload {
  x: string;
  y: string;
  z: string;
  pricingDetails: Record<string, unknown>;
  counterpartyMetadata: Record<string, unknown>;
  internalRiskNotes: Record<string, unknown>;
}

export interface TradeObject {
  publicHeader: TradePublicHeader;
  privatePayload: TradePrivatePayload;
}

export interface PolicyBundle {
  fields: string[];
  description: string;
}

export interface TradePolicy {
  policyId: string;
  policyName: string;
  version: string;
  objectType: string;
  bundleClasses: Record<string, PolicyBundle>;
  roleBindings: Record<InstitutionId, string[]>;
  constraints: {
    regulatorDisclosureRequiresLawfulBasis: boolean;
    recordPublicReceipt: boolean;
    revocationUsesEpoch: boolean;
    proofOnlyAssertionsAllowed: boolean;
  };
}

export type PublicEventName =
  | 'InstitutionRegistered'
  | 'PolicyAttached'
  | 'StakeholderSetUpdated'
  | 'ObjectCreated'
  | 'ObjectVersioned'
  | 'LifecycleTransitioned'
  | 'DisclosureRecorded'
  | 'ComplianceProofRecorded'
  | 'SettlementBound'
  | 'SettlementCompleted'
  | 'RevocationEpochAdvanced'
  | 'ObjectCancelled';

export interface PublicEvent {
  at: string;
  name: PublicEventName;
  data: Record<string, unknown>;
}
