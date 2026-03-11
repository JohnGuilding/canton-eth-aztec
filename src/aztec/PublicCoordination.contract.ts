// PublicCoordination.contract.ts
// Aztec app-contract-inspired sketch of the public coordination plane.
// This is not wired to the Aztec SDK here; it documents the intended surface.

export interface PublicCoordinationSurface {
  registerInstitution(id: string, role: string, publicKey: string): void;
  attachPolicy(objectId: string, policyHash: string): void;
  createObject(headerCommitment: string): void;
  versionObject(objectId: string, version: number, parentVersionHash: string, fieldRoot: string): void;
  transitionLifecycle(objectId: string, version: number, toState: string): void;
  updateStakeholderSet(objectId: string, stakeholderRoot: string): void;
  recordDisclosureReceipt(objectId: string, version: number, receiptId: string, lawfulBasisHash: string): void;
  recordComplianceProof(objectId: string, version: number, proofCommitment: string, complianceRoot: string): void;
  bindSettlement(objectId: string, settlementRef: string): void;
  completeSettlement(objectId: string, settlementRef: string): void;
  advanceRevocationEpoch(objectId: string, nextEpoch: number): void;
  cancelObject(objectId: string, reasonHash: string): void;
}

export const PublicEvents = [
  'ObjectCreated',
  'ObjectVersioned',
  'LifecycleTransitioned',
  'PolicyAttached',
  'StakeholderSetUpdated',
  'DisclosureRecorded',
  'ComplianceProofRecorded',
  'SettlementBound',
  'SettlementCompleted',
  'RevocationEpochAdvanced',
  'ObjectCancelled',
] as const;
