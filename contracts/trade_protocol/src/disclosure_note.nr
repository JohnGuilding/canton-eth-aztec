use aztec::{macros::notes::note, protocol::{traits::Packable, address::AztecAddress}};

// DisclosureNote is a receipt proving that a selective disclosure occurred.
// Created for both the discloser and the recipient (e.g., regulator).
// The receipt_id commits to the disclosed fields and lawful basis.
#[derive(Eq, Packable)]
#[note]
pub struct DisclosureNote {
    pub owner: AztecAddress,
    pub object_id: Field,
    pub version: Field,
    pub counterpart: Field,
    pub bundle_class: Field,
    pub lawful_basis_hash: Field,
    pub receipt_id: Field,
}

impl DisclosureNote {
    pub fn new(
        owner: AztecAddress,
        object_id: Field,
        version: Field,
        counterpart: Field,
        bundle_class: Field,
        lawful_basis_hash: Field,
        receipt_id: Field,
    ) -> Self {
        Self { owner, object_id, version, counterpart, bundle_class, lawful_basis_hash, receipt_id }
    }
}
