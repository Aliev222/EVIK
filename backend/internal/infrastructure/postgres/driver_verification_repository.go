package postgres

import (
	"context"
	"database/sql"
	"time"

	"evik/backend/internal/transport/http"
)

type DriverVerificationRepository struct {
	db *sql.DB
}

func NewDriverVerificationRepository(db *sql.DB) *DriverVerificationRepository {
	return &DriverVerificationRepository{db: db}
}

func (r *DriverVerificationRepository) GetVerificationStatus(ctx context.Context, driverID string) (*http.DriverVerificationStatus, error) {
	// Query the verification record
	var verificationID, status, adminComments string
	var submittedAt, updatedAt time.Time
	var submittedAtPtr, updatedAtPtr *time.Time

	verificationQuery := `
		SELECT id, status, submitted_at, updated_at, admin_comments
		FROM driver_verifications
		WHERE driver_id = $1
		ORDER BY submitted_at DESC
		LIMIT 1
	`

	err := r.db.QueryRowContext(ctx, verificationQuery, driverID).Scan(
		&verificationID, &status, &submittedAt, &updatedAt, &adminComments,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // No verification record found
		}
		return nil, err
	}

	submittedAtPtr = &submittedAt
	updatedAtPtr = &updatedAt

	// Query the uploaded documents
	documentsQuery := `
		SELECT document_type, public_url, uploaded_at, content_type
		FROM driver_documents
		WHERE verification_id = $1
		ORDER BY uploaded_at DESC
	`

	rows, err := r.db.QueryContext(ctx, documentsQuery, verificationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	documentsUploaded := make(map[string]http.DocumentInfo)
	for rows.Next() {
		var docType, publicURL, contentType string
		var uploadedAt time.Time

		if err := rows.Scan(&docType, &publicURL, &uploadedAt, &contentType); err != nil {
			return nil, err
		}

		documentsUploaded[docType] = http.DocumentInfo{
			URL:         publicURL,
			UploadedAt:  uploadedAt,
			ContentType: contentType,
		}
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return &http.DriverVerificationStatus{
		DriverID:         driverID,
		Status:           status,
		DocumentsUploaded: documentsUploaded,
		SubmittedAt:      submittedAtPtr,
		UpdatedAt:        updatedAtPtr,
		AdminComments:    adminComments,
	}, nil
}

// CreateVerification creates a new verification record and stores documents
func (r *DriverVerificationRepository) CreateVerification(ctx context.Context, driverID string, documents map[string]http.DocumentInfo) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// Insert or update verification record
	verificationQuery := `
		INSERT INTO driver_verifications (driver_id, status, submitted_at, updated_at)
		VALUES ($1, 'pending', NOW(), NOW())
		ON CONFLICT (driver_id)
		DO UPDATE SET status = 'pending', submitted_at = NOW(), updated_at = NOW(), admin_comments = ''
		RETURNING id
	`

	var verificationID string
	if err := tx.QueryRowContext(ctx, verificationQuery, driverID).Scan(&verificationID); err != nil {
		return err
	}

	// Delete old documents for this verification
	deleteDocsQuery := `DELETE FROM driver_documents WHERE verification_id = $1`
	if _, err := tx.ExecContext(ctx, deleteDocsQuery, verificationID); err != nil {
		return err
	}

	// Insert new documents
	for docType, docInfo := range documents {
		insertDocQuery := `
			INSERT INTO driver_documents (verification_id, document_type, storage_key, public_url, content_type, uploaded_at)
			VALUES ($1, $2, '', $3, $4, $5)
		`
		if _, err := tx.ExecContext(ctx, insertDocQuery, verificationID, docType, docInfo.URL, docInfo.ContentType, docInfo.UploadedAt); err != nil {
			return err
		}
	}

	// Create audit log entry
	auditQuery := `
		INSERT INTO moderation_audit_log (verification_id, action, previous_status, new_status, timestamp)
		VALUES ($1, 'submit', 'not_submitted', 'pending', NOW())
	`
	if _, err := tx.ExecContext(ctx, auditQuery, verificationID); err != nil {
		return err
	}

	return tx.Commit()
}