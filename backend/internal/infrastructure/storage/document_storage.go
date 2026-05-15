package storage

import (
	"context"
	"crypto/rand"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

type DocumentStorage struct {
	client          *minio.Client
	bucket          string
	publicBaseURL   string
}

type UploadedDocument struct {
	Key       string
	PublicURL string
	Size      int64
}

func NewDocumentStorage(endpoint, accessKey, secretKey, bucket, region, publicBaseURL string) (*DocumentStorage, error) {
	// Determine if we need SSL
	useSSL := strings.HasPrefix(endpoint, "https://")
	if useSSL {
		endpoint = strings.TrimPrefix(endpoint, "https://")
	} else {
		endpoint = strings.TrimPrefix(endpoint, "http://")
	}

	client, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(accessKey, secretKey, ""),
		Secure: useSSL,
		Region: region,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create minio client: %w", err)
	}

	return &DocumentStorage{
		client:        client,
		bucket:        bucket,
		publicBaseURL: strings.TrimSuffix(publicBaseURL, "/"),
	}, nil
}

func (ds *DocumentStorage) EnsureBucket(ctx context.Context) error {
	exists, err := ds.client.BucketExists(ctx, ds.bucket)
	if err != nil {
		return fmt.Errorf("failed to check bucket existence: %w", err)
	}
	if !exists {
		err = ds.client.MakeBucket(ctx, ds.bucket, minio.MakeBucketOptions{})
		if err != nil {
			return fmt.Errorf("failed to create bucket: %w", err)
		}
	}
	return nil
}

func (ds *DocumentStorage) UploadDocument(ctx context.Context, driverID, documentType string, reader io.Reader, size int64, contentType string) (*UploadedDocument, error) {
	// Generate unique filename
	timestamp := time.Now().Format("20060102-150405")
	randomBytes := make([]byte, 4)
	if _, err := rand.Read(randomBytes); err != nil {
		return nil, fmt.Errorf("failed to generate random bytes: %w", err)
	}
	randomSuffix := fmt.Sprintf("%x", randomBytes)

	// Determine file extension from content type
	var ext string
	switch contentType {
	case "image/jpeg":
		ext = ".jpg"
	case "image/png":
		ext = ".png"
	case "image/webp":
		ext = ".webp"
	case "application/pdf":
		ext = ".pdf"
	default:
		ext = ".bin"
	}

	key := fmt.Sprintf("drivers/%s/%s/%s-%s%s", driverID, documentType, timestamp, randomSuffix, ext)

	// Upload to S3/MinIO
	info, err := ds.client.PutObject(ctx, ds.bucket, key, reader, size, minio.PutObjectOptions{
		ContentType: contentType,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to upload to storage: %w", err)
	}

	// Construct public URL
	publicURL := fmt.Sprintf("%s/%s/%s", ds.publicBaseURL, ds.bucket, key)

	return &UploadedDocument{
		Key:       key,
		PublicURL: publicURL,
		Size:      info.Size,
	}, nil
}

func (ds *DocumentStorage) DeleteDocument(ctx context.Context, key string) error {
	err := ds.client.RemoveObject(ctx, ds.bucket, key, minio.RemoveObjectOptions{})
	if err != nil {
		return fmt.Errorf("failed to delete document: %w", err)
	}
	return nil
}

// Helper function to extract file extension from content type
func getFileExtension(contentType string) string {
	switch contentType {
	case "image/jpeg":
		return ".jpg"
	case "image/png":
		return ".png"
	case "image/gif":
		return ".gif"
	case "image/webp":
		return ".webp"
	case "application/pdf":
		return ".pdf"
	default:
		return ".bin"
	}
}

// Helper function to validate allowed document types
func IsAllowedDocumentType(documentType string) bool {
	allowed := map[string]bool{
		"passport":          true,
		"license":           true,
		"vehicleDocs":       true,
		"vehiclePhoto":      true,
		"selfie":           true,
	}
	return allowed[documentType]
}

// Helper function to validate content types
func IsAllowedContentType(contentType string) bool {
	allowed := map[string]bool{
		"image/jpeg":       true,
		"image/png":        true,
		"image/webp":       true,
		"application/pdf":  true,
	}
	return allowed[contentType]
}