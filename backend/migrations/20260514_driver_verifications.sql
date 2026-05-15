-- +goose Up
-- Phase 7: Driver document verification system
-- driver_verifications and moderation_audit_log are already created by ensureSchema()
-- with the extended (current) structure. This migration only adds objects and
-- constraints that are not already provided by ensureSchema.

-- driver_verifications table is created by ensureSchema with an extended schema
-- (user_id, full_name, vehicle_model, etc.). Do NOT recreate it here.

-- Ensure only one verification record per user (ensureSchema only provides a
-- non-unique idx_driver_verifications_user_id).
CREATE UNIQUE INDEX IF NOT EXISTS idx_driver_verifications_user_id_unique
    ON driver_verifications (user_id);

-- Index for admin queries by status and submission time
CREATE INDEX IF NOT EXISTS idx_driver_verifications_status_submitted
    ON driver_verifications (status, submitted_at DESC);

-- Driver uploaded documents: individual files uploaded by drivers
-- (not present in ensureSchema — keep CREATE TABLE here)
CREATE TABLE IF NOT EXISTS driver_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    verification_id TEXT NOT NULL,
    document_type TEXT NOT NULL,
    storage_key TEXT NOT NULL,
    public_url TEXT NOT NULL,
    content_type TEXT NOT NULL,
    file_size_bytes BIGINT NOT NULL DEFAULT 0,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (verification_id) REFERENCES driver_verifications(id) ON DELETE CASCADE
);

-- Index for querying documents by verification and type
CREATE INDEX IF NOT EXISTS idx_driver_documents_verification_type
    ON driver_documents (verification_id, document_type);

-- moderation_audit_log table is already created by ensureSchema with a different
-- column layout (entity_type/entity_id/action/reason/moderator_id/created_at).
-- We don't recreate it, and we skip the verification_id/timestamp index because
-- those columns don't exist in the ensureSchema version of the table.

-- Add constraint for valid verification statuses
ALTER TABLE driver_verifications
    DROP CONSTRAINT IF EXISTS driver_verifications_status_check;

ALTER TABLE driver_verifications
    ADD CONSTRAINT driver_verifications_status_check
    CHECK (status IN ('pending', 'approved', 'rejected', 'changes_requested', 'blocked'));

-- Add constraint for valid document types
ALTER TABLE driver_documents
    DROP CONSTRAINT IF EXISTS driver_documents_type_check;

ALTER TABLE driver_documents
    ADD CONSTRAINT driver_documents_type_check
    CHECK (document_type IN ('passport', 'license', 'vehicleDocs', 'vehiclePhoto', 'selfie'));

-- Add constraint for valid audit actions (action column exists in ensureSchema version too)
ALTER TABLE moderation_audit_log
    DROP CONSTRAINT IF EXISTS moderation_audit_log_action_check;

ALTER TABLE moderation_audit_log
    ADD CONSTRAINT moderation_audit_log_action_check
    CHECK (action IN ('approve', 'reject', 'request_changes', 'block', 'submit'));

-- +goose Down
-- not implemented (forward-only migration)
SELECT 1;
