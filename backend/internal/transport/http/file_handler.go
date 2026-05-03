package http

import (
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
)

type FileHandler struct {
	uploadPath string
	baseURL    string
}

func NewFileHandler(uploadPath, baseURL string) *FileHandler {
	// Создаем директорию для загрузок если не существует
	os.MkdirAll(uploadPath, 0755)
	return &FileHandler{
		uploadPath: uploadPath,
		baseURL:    baseURL,
	}
}

type FileUploadResponse struct {
	ID           string `json:"id"`
	OriginalName string `json:"original_name"`
	PublicURL    string `json:"public_url"`
	Size         int64  `json:"size"`
	MimeType     string `json:"mime_type"`
	CreatedAt    string `json:"created_at"`
}

type UploadedFile struct {
	ID           string
	OriginalName string
	FileName     string
	FilePath     string
	Size         int64
	MimeType     string
	DocumentType string // для документов водителя
	PhotoType    string // для фото заказов
	DriverID     string
	OrderID      string
	CreatedAt    time.Time
}

// In-memory storage для demo (в продакшене - база данных)
var uploadedFiles = make(map[string]*UploadedFile)

// POST /api/v1/driver/documents
func (h *FileHandler) UploadDriverDocument(w http.ResponseWriter, r *http.Request) {
	// Парсим multipart form
	err := r.ParseMultipartForm(10 << 20) // 10MB max
	if err != nil {
		h.writeError(w, http.StatusBadRequest, "Failed to parse form")
		return
	}

	// Извлекаем файл
	file, fileHeader, err := r.FormFile("document")
	if err != nil {
		h.writeError(w, http.StatusBadRequest, "Missing document file")
		return
	}
	defer file.Close()

	// Извлекаем дополнительные поля
	documentType := r.FormValue("document_type")
	driverID := r.FormValue("driver_id")

	// Валидация
	if documentType == "" {
		h.writeError(w, http.StatusBadRequest, "Missing document_type")
		return
	}

	if !h.isValidDocumentType(documentType) {
		h.writeError(w, http.StatusBadRequest, "Invalid document_type")
		return
	}

	if !h.isValidFileType(fileHeader.Filename) {
		h.writeError(w, http.StatusBadRequest, "Invalid file type. Only jpg, png, pdf allowed")
		return
	}

	if fileHeader.Size > 10<<20 {
		h.writeError(w, http.StatusBadRequest, "File too large. Max 10MB allowed")
		return
	}

	// Сохраняем файл
	uploadedFile, err := h.saveFile(file, fileHeader, driverID, documentType, "")
	if err != nil {
		h.writeError(w, http.StatusInternalServerError, "Failed to save file")
		return
	}

	// Сохраняем в "базе данных"
	uploadedFiles[uploadedFile.ID] = uploadedFile

	response := FileUploadResponse{
		ID:           uploadedFile.ID,
		OriginalName: uploadedFile.OriginalName,
		PublicURL:    uploadedFile.FilePath, // В продакшене - CDN URL
		Size:         uploadedFile.Size,
		MimeType:     uploadedFile.MimeType,
		CreatedAt:    uploadedFile.CreatedAt.Format(time.RFC3339),
	}

	h.writeJSON(w, http.StatusOK, response)
}

// POST /api/v1/orders/{orderId}/photos
func (h *FileHandler) UploadOrderPhoto(w http.ResponseWriter, r *http.Request) {
	orderID := chi.URLParam(r, "orderId")

	// Парсим multipart form
	err := r.ParseMultipartForm(10 << 20) // 10MB max
	if err != nil {
		h.writeError(w, http.StatusBadRequest, "Failed to parse form")
		return
	}

	// Извлекаем файл
	file, fileHeader, err := r.FormFile("photo")
	if err != nil {
		h.writeError(w, http.StatusBadRequest, "Missing photo file")
		return
	}
	defer file.Close()

	// Извлекаем тип фото
	photoType := r.FormValue("photo_type")
	if !h.isValidPhotoType(photoType) {
		h.writeError(w, http.StatusBadRequest, "Invalid photo_type")
		return
	}

	if !h.isValidImageType(fileHeader.Filename) {
		h.writeError(w, http.StatusBadRequest, "Invalid file type. Only jpg, png allowed")
		return
	}

	// Сохраняем файл
	uploadedFile, err := h.saveFile(file, fileHeader, "", "", orderID)
	if err != nil {
		h.writeError(w, http.StatusInternalServerError, "Failed to save file")
		return
	}

	uploadedFile.PhotoType = photoType
	uploadedFiles[uploadedFile.ID] = uploadedFile

	response := FileUploadResponse{
		ID:           uploadedFile.ID,
		OriginalName: uploadedFile.OriginalName,
		PublicURL:    uploadedFile.FilePath,
		Size:         uploadedFile.Size,
		MimeType:     uploadedFile.MimeType,
		CreatedAt:    uploadedFile.CreatedAt.Format(time.RFC3339),
	}

	h.writeJSON(w, http.StatusOK, response)
}

// GET /api/v1/files/{fileId}
func (h *FileHandler) ServeFile(w http.ResponseWriter, r *http.Request) {
	fileID := chi.URLParam(r, "fileId")

	uploadedFile, exists := uploadedFiles[fileID]
	if !exists {
		h.writeError(w, http.StatusNotFound, "File not found")
		return
	}

	// Читаем файл с диска
	fullPath := filepath.Join(h.uploadPath, uploadedFile.FileName)
	fileData, err := os.ReadFile(fullPath)
	if err != nil {
		h.writeError(w, http.StatusNotFound, "File not found on disk")
		return
	}

	// Устанавливаем заголовки
	w.Header().Set("Content-Type", uploadedFile.MimeType)
	w.Header().Set("Content-Length", strconv.Itoa(len(fileData)))
	w.Header().Set("Content-Disposition", fmt.Sprintf("inline; filename=\"%s\"", uploadedFile.OriginalName))

	// Отправляем файл
	w.WriteHeader(http.StatusOK)
	w.Write(fileData)
}

func (h *FileHandler) saveFile(file multipart.File, fileHeader *multipart.FileHeader, driverID, documentType, orderID string) (*UploadedFile, error) {
	// Генерируем уникальное имя файла
	fileID := uuid.New().String()
	ext := filepath.Ext(fileHeader.Filename)
	fileName := fileID + ext
	filePath := filepath.Join(h.uploadPath, fileName)

	// Создаем файл на диске
	dst, err := os.Create(filePath)
	if err != nil {
		return nil, err
	}
	defer dst.Close()

	// Копируем содержимое
	_, err = io.Copy(dst, file)
	if err != nil {
		return nil, err
	}

	// Определяем MIME тип
	mimeType := "application/octet-stream"
	if strings.HasSuffix(strings.ToLower(fileHeader.Filename), ".jpg") ||
		strings.HasSuffix(strings.ToLower(fileHeader.Filename), ".jpeg") {
		mimeType = "image/jpeg"
	} else if strings.HasSuffix(strings.ToLower(fileHeader.Filename), ".png") {
		mimeType = "image/png"
	} else if strings.HasSuffix(strings.ToLower(fileHeader.Filename), ".pdf") {
		mimeType = "application/pdf"
	}

	return &UploadedFile{
		ID:           fileID,
		OriginalName: fileHeader.Filename,
		FileName:     fileName,
		FilePath:     filePath,
		Size:         fileHeader.Size,
		MimeType:     mimeType,
		DocumentType: documentType,
		DriverID:     driverID,
		OrderID:      orderID,
		CreatedAt:    time.Now(),
	}, nil
}

func (h *FileHandler) isValidDocumentType(docType string) bool {
	validTypes := []string{"passport", "license", "vehicle_registration", "selfie"}
	for _, valid := range validTypes {
		if docType == valid {
			return true
		}
	}
	return false
}

func (h *FileHandler) isValidPhotoType(photoType string) bool {
	validTypes := []string{"before", "after", "damage"}
	for _, valid := range validTypes {
		if photoType == valid {
			return true
		}
	}
	return false
}

func (h *FileHandler) isValidFileType(filename string) bool {
	lower := strings.ToLower(filename)
	return strings.HasSuffix(lower, ".jpg") ||
		strings.HasSuffix(lower, ".jpeg") ||
		strings.HasSuffix(lower, ".png") ||
		strings.HasSuffix(lower, ".pdf")
}

func (h *FileHandler) isValidImageType(filename string) bool {
	lower := strings.ToLower(filename)
	return strings.HasSuffix(lower, ".jpg") ||
		strings.HasSuffix(lower, ".jpeg") ||
		strings.HasSuffix(lower, ".png")
}

func (h *FileHandler) writeJSON(w http.ResponseWriter, status int, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(payload)
}

func (h *FileHandler) writeError(w http.ResponseWriter, status int, message string) {
	h.writeJSON(w, status, map[string]string{"error": message})
}