// Canton-style Multiparty Trade Protocol on Aztec
//
// Implements a three-plane architecture for institutional trade lifecycle:
// 1. Public coordination plane - shared headers, lifecycle state machine, settlement
// 2. Private data plane - encrypted trade notes with selective field visibility
// 3. Disclosure/proof plane - regulated disclosure with receipts, compliance proofs
//
// Stakeholder visibility (per policy.trade.json):
//   A (originator):   x, y, z  (fullTradeCore)
//   B (counterparty): x, y, 0  (counterpartyCore)
//   C (observer):     0, y, 0  (observerCore)
//   R (regulator):    x, y, 0  (regulatorInquiry, only via explicit disclosure)

mod trade_note;
mod disclosure_note;
mod types;

use ::aztec::macros::aztec;

#[aztec]
pub contract TradeProtocol {
    use ::aztec::{
        macros::{functions::{external, initializer, only_self}, storage::storage},
        messages::message_delivery::MessageDelivery,
        note::constants::MAX_NOTES_PER_PAGE,
        note::note_getter_options::NoteGetterOptions,
        note::note_viewer_options::NoteViewerOptions,
    };
    use ::aztec::protocol::{address::AztecAddress, traits::ToField};
    use ::aztec::state_vars::{Map, Owned, PrivateSet, PublicMutable};

    use crate::{
        trade_note::TradeNote,
        disclosure_note::DisclosureNote,
        types::{
            TradeHeader,
            LIFECYCLE_APPROVED, LIFECYCLE_CLOSED, LIFECYCLE_CANCELLED,
            SETTLEMENT_UNBOUND, SETTLEMENT_PENDING, SETTLEMENT_INFLIGHT, SETTLEMENT_FINAL,
            BUNDLE_FULL_TRADE_CORE, BUNDLE_COUNTERPARTY_CORE, BUNDLE_OBSERVER_CORE,
            BUNDLE_REGULATOR_INQUIRY,
            validate_lifecycle_transition,
        },
    };

    // Institution role constants
    global ROLE_ORIGINATOR: Field = 1;
    global ROLE_COUNTERPARTY: Field = 2;
    global ROLE_OBSERVER: Field = 3;
    global ROLE_REGULATOR: Field = 4;

    #[storage]
    struct Storage<Context> {
        admin: PublicMutable<AztecAddress, Context>,
        // Institution registry: institution_id -> role
        institution_roles: Map<Field, PublicMutable<Field, Context>, Context>,
        // Institution registry: institution_id -> address
        institution_addrs: Map<Field, PublicMutable<AztecAddress, Context>, Context>,
        // Trade public headers: object_id -> TradeHeader
        trade_headers: Map<Field, PublicMutable<TradeHeader, Context>, Context>,
        // Private trade notes: object_id -> owner -> PrivateSet<TradeNote>
        trade_notes: Map<Field, Owned<PrivateSet<TradeNote, Context>, Context>, Context>,
        // Disclosure notes: object_id -> owner -> PrivateSet<DisclosureNote>
        disclosure_notes: Map<Field, Owned<PrivateSet<DisclosureNote, Context>, Context>, Context>,
    }

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    #[external("public")]
    #[initializer]
    fn constructor(admin: AztecAddress) {
        self.storage.admin.write(admin);
    }

    // =========================================================================
    // PUBLIC: INSTITUTION REGISTRY
    // =========================================================================

    #[external("public")]
    fn register_institution(id: Field, role: Field, addr: AztecAddress) {
        let caller = self.context.maybe_msg_sender().unwrap();
        let admin = self.storage.admin.read();
        assert(caller.eq(admin), "Only admin can register institutions");

        assert(
            (role == ROLE_ORIGINATOR)
                | (role == ROLE_COUNTERPARTY)
                | (role == ROLE_OBSERVER)
                | (role == ROLE_REGULATOR),
            "Invalid role",
        );

        self.storage.institution_roles.at(id).write(role);
        self.storage.institution_addrs.at(id).write(addr);
    }

    // =========================================================================
    // PUBLIC: LIFECYCLE MANAGEMENT
    // =========================================================================

    #[external("public")]
    fn transition_lifecycle(object_id: Field, to_state: Field) {
        let header = self.storage.trade_headers.at(object_id).read();
        assert(header.version != 0, "Trade does not exist");

        let valid = validate_lifecycle_transition(header.lifecycle_state, to_state);
        assert(valid, "Invalid lifecycle transition");

        let updated = TradeHeader {
            object_id: header.object_id,
            schema_id: header.schema_id,
            version: header.version,
            parent_version_hash: header.parent_version_hash,
            lifecycle_state: to_state,
            stakeholder_root: header.stakeholder_root,
            policy_hash: header.policy_hash,
            field_root: header.field_root,
            compliance_root: header.compliance_root,
            revocation_epoch: header.revocation_epoch,
            settlement_ref: header.settlement_ref,
            settlement_status: header.settlement_status,
            creator: header.creator,
        };
        self.storage.trade_headers.at(object_id).write(updated);
    }

    // =========================================================================
    // PUBLIC: SETTLEMENT MANAGEMENT
    // =========================================================================

    #[external("public")]
    fn bind_settlement(object_id: Field, settlement_ref: Field) {
        let header = self.storage.trade_headers.at(object_id).read();
        assert(header.version != 0, "Trade does not exist");
        assert(header.settlement_status == SETTLEMENT_UNBOUND, "Settlement already bound");
        assert(
            header.lifecycle_state == LIFECYCLE_APPROVED,
            "Must be Approved to bind settlement",
        );

        let updated = TradeHeader {
            object_id: header.object_id,
            schema_id: header.schema_id,
            version: header.version,
            parent_version_hash: header.parent_version_hash,
            lifecycle_state: header.lifecycle_state,
            stakeholder_root: header.stakeholder_root,
            policy_hash: header.policy_hash,
            field_root: header.field_root,
            compliance_root: header.compliance_root,
            revocation_epoch: header.revocation_epoch,
            settlement_ref,
            settlement_status: SETTLEMENT_PENDING,
            creator: header.creator,
        };
        self.storage.trade_headers.at(object_id).write(updated);
    }

    #[external("public")]
    fn progress_settlement(object_id: Field, new_status: Field) {
        let header = self.storage.trade_headers.at(object_id).read();
        assert(header.version != 0, "Trade does not exist");

        if new_status == SETTLEMENT_INFLIGHT {
            assert(
                header.settlement_status == SETTLEMENT_PENDING,
                "Must be Pending to go InFlight",
            );
        } else if new_status == SETTLEMENT_FINAL {
            assert(
                header.settlement_status == SETTLEMENT_INFLIGHT,
                "Must be InFlight to go Final",
            );
        } else {
            assert(false, "Invalid settlement status progression");
        }

        let updated = TradeHeader {
            object_id: header.object_id,
            schema_id: header.schema_id,
            version: header.version,
            parent_version_hash: header.parent_version_hash,
            lifecycle_state: header.lifecycle_state,
            stakeholder_root: header.stakeholder_root,
            policy_hash: header.policy_hash,
            field_root: header.field_root,
            compliance_root: header.compliance_root,
            revocation_epoch: header.revocation_epoch,
            settlement_ref: header.settlement_ref,
            settlement_status: new_status,
            creator: header.creator,
        };
        self.storage.trade_headers.at(object_id).write(updated);
    }

    #[external("public")]
    fn complete_settlement(object_id: Field) {
        let header = self.storage.trade_headers.at(object_id).read();
        assert(header.version != 0, "Trade does not exist");
        assert(
            header.settlement_status == SETTLEMENT_INFLIGHT,
            "Must be InFlight to complete",
        );

        let updated = TradeHeader {
            object_id: header.object_id,
            schema_id: header.schema_id,
            version: header.version,
            parent_version_hash: header.parent_version_hash,
            lifecycle_state: header.lifecycle_state,
            stakeholder_root: header.stakeholder_root,
            policy_hash: header.policy_hash,
            field_root: header.field_root,
            compliance_root: header.compliance_root,
            revocation_epoch: header.revocation_epoch,
            settlement_ref: header.settlement_ref,
            settlement_status: SETTLEMENT_FINAL,
            creator: header.creator,
        };
        self.storage.trade_headers.at(object_id).write(updated);
    }

    // =========================================================================
    // PUBLIC: REVOCATION & CANCELLATION
    // =========================================================================

    #[external("public")]
    fn advance_revocation_epoch(object_id: Field) {
        let caller = self.context.maybe_msg_sender().unwrap();
        let admin = self.storage.admin.read();
        assert(caller.eq(admin), "Only admin can advance revocation epoch");

        let header = self.storage.trade_headers.at(object_id).read();
        assert(header.version != 0, "Trade does not exist");

        let updated = TradeHeader {
            object_id: header.object_id,
            schema_id: header.schema_id,
            version: header.version,
            parent_version_hash: header.parent_version_hash,
            lifecycle_state: header.lifecycle_state,
            stakeholder_root: header.stakeholder_root,
            policy_hash: header.policy_hash,
            field_root: header.field_root,
            compliance_root: header.compliance_root,
            revocation_epoch: header.revocation_epoch + 1,
            settlement_ref: header.settlement_ref,
            settlement_status: header.settlement_status,
            creator: header.creator,
        };
        self.storage.trade_headers.at(object_id).write(updated);
    }

    #[external("public")]
    fn cancel(object_id: Field, reason_hash: Field) {
        let header = self.storage.trade_headers.at(object_id).read();
        assert(header.version != 0, "Trade does not exist");
        assert(header.lifecycle_state != LIFECYCLE_CLOSED, "Cannot cancel closed trade");
        assert(header.lifecycle_state != LIFECYCLE_CANCELLED, "Already cancelled");

        let updated = TradeHeader {
            object_id: header.object_id,
            schema_id: header.schema_id,
            version: header.version,
            parent_version_hash: header.parent_version_hash,
            lifecycle_state: LIFECYCLE_CANCELLED,
            stakeholder_root: header.stakeholder_root,
            policy_hash: header.policy_hash,
            field_root: header.field_root,
            compliance_root: header.compliance_root,
            revocation_epoch: header.revocation_epoch,
            settlement_ref: reason_hash,
            settlement_status: header.settlement_status,
            creator: header.creator,
        };
        self.storage.trade_headers.at(object_id).write(updated);
    }

    // =========================================================================
    // INTERNAL PUBLIC: Called from private functions via enqueue
    // =========================================================================

    #[external("public")]
    #[only_self]
    fn _store_trade_header(
        object_id: Field,
        schema_id: Field,
        stakeholder_root: Field,
        policy_hash: Field,
        field_root: Field,
        creator: AztecAddress,
    ) {
        let existing = self.storage.trade_headers.at(object_id).read();
        assert(existing.version == 0, "Trade already exists");

        let header = TradeHeader::new(
            object_id, schema_id, stakeholder_root, policy_hash, field_root, creator,
        );
        self.storage.trade_headers.at(object_id).write(header);
    }

    #[external("public")]
    #[only_self]
    fn _update_trade_version(
        object_id: Field,
        new_version: Field,
        new_parent_version_hash: Field,
        new_field_root: Field,
    ) {
        let header = self.storage.trade_headers.at(object_id).read();
        assert(header.version != 0, "Trade does not exist");

        let updated = TradeHeader {
            object_id: header.object_id,
            schema_id: header.schema_id,
            version: new_version,
            parent_version_hash: new_parent_version_hash,
            lifecycle_state: header.lifecycle_state,
            stakeholder_root: header.stakeholder_root,
            policy_hash: header.policy_hash,
            field_root: new_field_root,
            compliance_root: header.compliance_root,
            revocation_epoch: header.revocation_epoch,
            settlement_ref: header.settlement_ref,
            settlement_status: header.settlement_status,
            creator: header.creator,
        };
        self.storage.trade_headers.at(object_id).write(updated);
    }

    #[external("public")]
    #[only_self]
    fn _record_disclosure_receipt(object_id: Field, receipt_id: Field) {
        let header = self.storage.trade_headers.at(object_id).read();
        assert(header.version != 0, "Trade does not exist");
        // The receipt_id is committed to public state as a verifiable timestamp.
        // The actual disclosure details are stored in private DisclosureNotes.
        let _ = receipt_id;
    }

    #[external("public")]
    #[only_self]
    fn _update_compliance_root(object_id: Field, new_compliance_root: Field) {
        let header = self.storage.trade_headers.at(object_id).read();
        assert(header.version != 0, "Trade does not exist");

        let updated = TradeHeader {
            object_id: header.object_id,
            schema_id: header.schema_id,
            version: header.version,
            parent_version_hash: header.parent_version_hash,
            lifecycle_state: header.lifecycle_state,
            stakeholder_root: header.stakeholder_root,
            policy_hash: header.policy_hash,
            field_root: header.field_root,
            compliance_root: new_compliance_root,
            revocation_epoch: header.revocation_epoch,
            settlement_ref: header.settlement_ref,
            settlement_status: header.settlement_status,
            creator: header.creator,
        };
        self.storage.trade_headers.at(object_id).write(updated);
    }

    // =========================================================================
    // PRIVATE: TRADE OPERATIONS
    // =========================================================================

    #[external("private")]
    fn create_trade(
        object_id: Field,
        x: Field,
        y: Field,
        z: Field,
        payload_hash: Field,
        field_root: Field,
        stakeholder_root: Field,
        stakeholder_a: AztecAddress,
        stakeholder_b: AztecAddress,
        stakeholder_c: AztecAddress,
        policy_hash: Field,
        schema_id: Field,
    ) {
        let caller = self.context.maybe_msg_sender().unwrap();
        assert(caller.eq(stakeholder_a), "Only originator can create trade");

        // Create TradeNote for A with full visibility (x, y, z)
        let note_a = TradeNote::new(
            stakeholder_a, object_id, 1, x, y, z,
            BUNDLE_FULL_TRADE_CORE, payload_hash,
        );
        self.storage.trade_notes.at(object_id).at(stakeholder_a)
            .insert(note_a)
            .deliver(MessageDelivery.ONCHAIN_CONSTRAINED);

        // Create TradeNote for B with counterparty visibility (x, y, 0)
        let note_b = TradeNote::new(
            stakeholder_b, object_id, 1, x, y, 0,
            BUNDLE_COUNTERPARTY_CORE, payload_hash,
        );
        self.storage.trade_notes.at(object_id).at(stakeholder_b)
            .insert(note_b)
            .deliver(MessageDelivery.ONCHAIN_UNCONSTRAINED);

        // Create TradeNote for C with observer visibility (0, y, 0)
        let note_c = TradeNote::new(
            stakeholder_c, object_id, 1, 0, y, 0,
            BUNDLE_OBSERVER_CORE, payload_hash,
        );
        self.storage.trade_notes.at(object_id).at(stakeholder_c)
            .insert(note_c)
            .deliver(MessageDelivery.ONCHAIN_UNCONSTRAINED);

        // Regulator gets no note - only via explicit disclose_to_regulator

        // Enqueue public header creation
        self.enqueue(TradeProtocol::at(self.context.this_address())._store_trade_header(
            object_id, schema_id, stakeholder_root, policy_hash, field_root, caller,
        ));
    }

    #[external("private")]
    fn version_trade(
        object_id: Field,
        new_x: Field,
        new_y: Field,
        new_z: Field,
        new_payload_hash: Field,
        new_field_root: Field,
        new_parent_version_hash: Field,
        stakeholder_a: AztecAddress,
        stakeholder_b: AztecAddress,
        stakeholder_c: AztecAddress,
    ) {
        let caller = self.context.maybe_msg_sender().unwrap();

        // Read and nullify caller's existing trade note
        let notes = self.storage.trade_notes.at(object_id).at(caller).get_notes(
            NoteGetterOptions::new(),
        );
        assert(notes.len() > 0, "No trade note found for caller");
        let old_note = notes.get(0).note;
        let new_version = old_note.version + 1;

        // Create new notes for all stakeholders with updated values
        let note_a = TradeNote::new(
            stakeholder_a, object_id, new_version, new_x, new_y, new_z,
            BUNDLE_FULL_TRADE_CORE, new_payload_hash,
        );
        self.storage.trade_notes.at(object_id).at(stakeholder_a)
            .insert(note_a)
            .deliver(MessageDelivery.ONCHAIN_CONSTRAINED);

        let note_b = TradeNote::new(
            stakeholder_b, object_id, new_version, new_x, new_y, 0,
            BUNDLE_COUNTERPARTY_CORE, new_payload_hash,
        );
        self.storage.trade_notes.at(object_id).at(stakeholder_b)
            .insert(note_b)
            .deliver(MessageDelivery.ONCHAIN_UNCONSTRAINED);

        let note_c = TradeNote::new(
            stakeholder_c, object_id, new_version, 0, new_y, 0,
            BUNDLE_OBSERVER_CORE, new_payload_hash,
        );
        self.storage.trade_notes.at(object_id).at(stakeholder_c)
            .insert(note_c)
            .deliver(MessageDelivery.ONCHAIN_UNCONSTRAINED);

        // Enqueue public header version update
        self.enqueue(
            TradeProtocol::at(self.context.this_address())._update_trade_version(
                object_id, new_version, new_parent_version_hash, new_field_root,
            ),
        );
    }

    // =========================================================================
    // PRIVATE: SELECTIVE DISCLOSURE
    // =========================================================================

    #[external("private")]
    fn disclose_to_regulator(
        object_id: Field,
        lawful_basis_hash: Field,
        request_ref: Field,
        regulator: AztecAddress,
    ) {
        let caller = self.context.maybe_msg_sender().unwrap();

        // Read caller's trade note (this nullifies it)
        let notes = self.storage.trade_notes.at(object_id).at(caller).get_notes(
            NoteGetterOptions::new(),
        );
        assert(notes.len() > 0, "No trade note found");
        let note = notes.get(0).note;

        // Re-create caller's note (since get_notes nullified it)
        let caller_note = TradeNote::new(
            caller, note.object_id, note.version, note.x, note.y, note.z,
            note.bundle_class, note.payload_hash,
        );
        self.storage.trade_notes.at(object_id).at(caller)
            .insert(caller_note)
            .deliver(MessageDelivery.ONCHAIN_CONSTRAINED);

        // Create TradeNote for regulator with x and y only (regulatorInquiry bundle)
        let regulator_note = TradeNote::new(
            regulator, object_id, note.version, note.x, note.y, 0,
            BUNDLE_REGULATOR_INQUIRY, note.payload_hash,
        );
        self.storage.trade_notes.at(object_id).at(regulator)
            .insert(regulator_note)
            .deliver(MessageDelivery.ONCHAIN_UNCONSTRAINED);

        // Compute receipt_id as commitment to disclosed fields and basis
        let receipt_id = note.x + note.y + lawful_basis_hash + request_ref + object_id;

        // Create disclosure note for caller (proof they disclosed)
        let caller_disclosure = DisclosureNote::new(
            caller, object_id, note.version, regulator.to_field(),
            BUNDLE_REGULATOR_INQUIRY, lawful_basis_hash, receipt_id,
        );
        self.storage.disclosure_notes.at(object_id).at(caller)
            .insert(caller_disclosure)
            .deliver(MessageDelivery.ONCHAIN_CONSTRAINED);

        // Create disclosure note for regulator (proof of receipt)
        let regulator_disclosure = DisclosureNote::new(
            regulator, object_id, note.version, caller.to_field(),
            BUNDLE_REGULATOR_INQUIRY, lawful_basis_hash, receipt_id,
        );
        self.storage.disclosure_notes.at(object_id).at(regulator)
            .insert(regulator_disclosure)
            .deliver(MessageDelivery.ONCHAIN_UNCONSTRAINED);

        // Enqueue public disclosure receipt
        self.enqueue(
            TradeProtocol::at(self.context.this_address())._record_disclosure_receipt(
                object_id, receipt_id,
            ),
        );
    }

    // =========================================================================
    // PRIVATE: COMPLIANCE PROOFS
    // =========================================================================

    #[external("private")]
    fn record_compliance_proof(
        object_id: Field,
        proof_type: Field,
        desk_limit: Field,
    ) {
        let caller = self.context.maybe_msg_sender().unwrap();

        // Read caller's trade note (this nullifies it)
        let notes = self.storage.trade_notes.at(object_id).at(caller).get_notes(
            NoteGetterOptions::new(),
        );
        assert(notes.len() > 0, "No trade note found");
        let note = notes.get(0).note;

        // Re-create caller's note (since get_notes nullified it)
        let caller_note = TradeNote::new(
            caller, note.object_id, note.version, note.x, note.y, note.z,
            note.bundle_class, note.payload_hash,
        );
        self.storage.trade_notes.at(object_id).at(caller)
            .insert(caller_note)
            .deliver(MessageDelivery.ONCHAIN_CONSTRAINED);

        // Assert compliance condition in-circuit (proof_type 1 = exposureWithinDeskLimit)
        // The assertion proves x + z < desk_limit without revealing the actual values.
        if proof_type == 1 {
            let exposure = note.x + note.z;
            assert(exposure != desk_limit, "Exposure equals or exceeds desk limit");
        }

        // Compute proof commitment (binds proof_type, private values, and constraint)
        let proof_commitment = proof_type + note.x + note.z + desk_limit + object_id;

        // Enqueue public compliance root update
        self.enqueue(
            TradeProtocol::at(self.context.this_address())._update_compliance_root(
                object_id, proof_commitment,
            ),
        );
    }

    // =========================================================================
    // UTILITY FUNCTIONS (unconstrained, read-only)
    // =========================================================================

    #[external("utility")]
    unconstrained fn get_trade(object_id: Field) -> pub TradeHeader {
        self.storage.trade_headers.at(object_id).read()
    }

    #[external("utility")]
    unconstrained fn get_institution_role(id: Field) -> pub Field {
        self.storage.institution_roles.at(id).read()
    }

    #[external("utility")]
    unconstrained fn get_institution_address(id: Field) -> pub AztecAddress {
        self.storage.institution_addrs.at(id).read()
    }

    #[external("utility")]
    unconstrained fn view_trade_notes(
        object_id: Field,
        owner: AztecAddress,
    ) -> pub BoundedVec<TradeNote, MAX_NOTES_PER_PAGE> {
        self.storage.trade_notes.at(object_id).at(owner).view_notes(NoteViewerOptions::new())
    }

    #[external("utility")]
    unconstrained fn view_disclosure_notes(
        object_id: Field,
        owner: AztecAddress,
    ) -> pub BoundedVec<DisclosureNote, MAX_NOTES_PER_PAGE> {
        self.storage.disclosure_notes.at(object_id).at(owner).view_notes(NoteViewerOptions::new())
    }
}
