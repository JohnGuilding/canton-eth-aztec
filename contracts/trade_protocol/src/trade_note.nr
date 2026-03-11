use aztec::{macros::notes::note, protocol::{traits::Packable, address::AztecAddress}};

// TradeNote stores a stakeholder's private view of a trade object.
// Each stakeholder receives a note with field visibility determined by their bundle class:
//   fullTradeCore (A):       x, y, z
//   counterpartyCore (B):    x, y, 0
//   observerCore (C):        0, y, 0
//   regulatorInquiry (R):    x, y, 0  (only via explicit disclosure)
//
// Fields set to 0 indicate "not visible to this stakeholder".
// The note is encrypted for the owner PXE - only they can decrypt it.
#[derive(Eq, Packable)]
#[note]
pub struct TradeNote {
    pub owner: AztecAddress,
    pub object_id: Field,
    pub version: Field,
    pub x: Field,
    pub y: Field,
    pub z: Field,
    pub bundle_class: Field,
    pub payload_hash: Field,
}

impl TradeNote {
    pub fn new(
        owner: AztecAddress,
        object_id: Field,
        version: Field,
        x: Field,
        y: Field,
        z: Field,
        bundle_class: Field,
        payload_hash: Field,
    ) -> Self {
        Self { owner, object_id, version, x, y, z, bundle_class, payload_hash }
    }
}
