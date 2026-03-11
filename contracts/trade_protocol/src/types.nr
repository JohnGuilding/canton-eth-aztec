use ::aztec::protocol::{
    address::AztecAddress,
    traits::{Deserialize, Serialize, Packable},
};

// Lifecycle state constants
pub global LIFECYCLE_DRAFT: Field = 0;
pub global LIFECYCLE_PROPOSED: Field = 1;
pub global LIFECYCLE_MATCHED: Field = 2;
pub global LIFECYCLE_APPROVED: Field = 3;
pub global LIFECYCLE_SETTLED: Field = 4;
pub global LIFECYCLE_CLOSED: Field = 5;
pub global LIFECYCLE_CANCELLED: Field = 6;

// Settlement status constants
pub global SETTLEMENT_UNBOUND: Field = 0;
pub global SETTLEMENT_PENDING: Field = 1;
pub global SETTLEMENT_INFLIGHT: Field = 2;
pub global SETTLEMENT_FINAL: Field = 3;

// Bundle class constants
pub global BUNDLE_FULL_TRADE_CORE: Field = 1;
pub global BUNDLE_COUNTERPARTY_CORE: Field = 2;
pub global BUNDLE_OBSERVER_CORE: Field = 3;
pub global BUNDLE_REGULATOR_INQUIRY: Field = 4;

// Trade public header - stored in public state, visible to all
#[derive(Deserialize, Serialize, Eq, Packable)]
pub struct TradeHeader {
    pub object_id: Field,
    pub schema_id: Field,
    pub version: Field,
    pub parent_version_hash: Field,
    pub lifecycle_state: Field,
    pub stakeholder_root: Field,
    pub policy_hash: Field,
    pub field_root: Field,
    pub compliance_root: Field,
    pub revocation_epoch: Field,
    pub settlement_ref: Field,
    pub settlement_status: Field,
    pub creator: AztecAddress,
}

impl TradeHeader {
    pub fn new(
        object_id: Field,
        schema_id: Field,
        stakeholder_root: Field,
        policy_hash: Field,
        field_root: Field,
        creator: AztecAddress,
    ) -> Self {
        Self {
            object_id,
            schema_id,
            version: 1,
            parent_version_hash: 0,
            lifecycle_state: LIFECYCLE_DRAFT,
            stakeholder_root,
            policy_hash,
            field_root,
            compliance_root: 0,
            revocation_epoch: 0,
            settlement_ref: 0,
            settlement_status: SETTLEMENT_UNBOUND,
            creator,
        }
    }
}

// Validates lifecycle transitions: forward-only, plus any non-terminal state -> Cancelled
pub fn validate_lifecycle_transition(from: Field, to: Field) -> bool {
    // Any non-terminal state can transition to Cancelled
    if to == LIFECYCLE_CANCELLED {
        (from != LIFECYCLE_CLOSED) & (from != LIFECYCLE_CANCELLED)
    } else if (from == LIFECYCLE_DRAFT) & (to == LIFECYCLE_PROPOSED) {
        true
    } else if (from == LIFECYCLE_PROPOSED) & (to == LIFECYCLE_MATCHED) {
        true
    } else if (from == LIFECYCLE_MATCHED) & (to == LIFECYCLE_APPROVED) {
        true
    } else if (from == LIFECYCLE_APPROVED) & (to == LIFECYCLE_SETTLED) {
        true
    } else if (from == LIFECYCLE_SETTLED) & (to == LIFECYCLE_CLOSED) {
        true
    } else {
        false
    }
}
