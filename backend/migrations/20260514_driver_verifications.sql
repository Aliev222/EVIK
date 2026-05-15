-- +goose Up
-- Phase 7: Driver document verification system
-- Creates tables to track driver document uploads, admin moderation decisions,
-- and the audit trail for verification status changes.

-- Driver document verifications: tracks the overall verification status
-- and metadata for a driver's document submission
CREATE TABLE IF NOT EXISTS driver_verifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    admin_comments TEXT DEFAULT '',
    FOREIGN KEY (driver_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Ensure only one verification record per driver
CREATE UNIQUE INDEX IF NOT EXISTS idx_driver_verifications_driver_id
    ON driver_verifications (driver_id);

-- Index for admin queries by status and submission time
CREATE INDEX IF NOT EXISTS idx_driver_verifications_status_submitted
    ON driver_verifications (status, submitted_at DESC);

-- Driver uploaded documents: individual files uploaded by drivers
CREATE TABLE IF NOT EXISTS driver_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    verification_id UUID NOT NULL,
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

-- Moderation audit log: tracks all admin decisions and status changes
CREATE TABLE IF NOT EXISTS moderation_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    verification_id UUID NOT NULL,
    admin_user_id TEXT,
    action TEXT NOT NULL, -- 'approve', 'reject', 'request_changes', 'block'
    previous_status TEXT NOT NULL,
    new_status TEXT NOT NULL,
    comments TEXT DEFAULT '',
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (verification_id) REFERENCES driver_verifications(id) ON DELETE CASCADE
);

-- Index for audit trail queries
CREATE INDEX IF NOT EXISTS idx_moderation_audit_log_verification_timestamp
    ON moderation_audit_log (verification_id, timestamp DESC);

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

-- Add constraint for valid audit actions
ALTER TABLE moderation_audit_log
    DROP CONSTRAINT IF EXISTS moderation_audit_log_action_check;

ALTER TABLE moderation_audit_log
    ADD CONSTRAINT moderation_audit_log_action_check
    CHECK (action IN ('approve', 'reject', 'request_changes', 'block', 'submit'));

-- +goose Down
-- not implemented (forward-only migration)
SELECT 1;