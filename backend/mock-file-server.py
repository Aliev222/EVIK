#!/usr/bin/env python3
"""
Mock File Upload Server for EVIK Testing
Simple Flask server to test Flutter file upload functionality
"""

from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
import uuid
import os
import time
from datetime import datetime
from werkzeug.utils import secure_filename

app = Flask(__name__)
CORS(app)

# Configuration
UPLOAD_FOLDER = 'uploads'
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10MB
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'pdf'}
ALLOWED_DOCUMENT_TYPES = {'passport', 'license', 'vehicle_registration', 'selfie'}
ALLOWED_PHOTO_TYPES = {'before', 'after', 'damage'}

# Ensure upload folder exists
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# In-memory file storage
uploaded_files = {}

def allowed_file(filename):
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def get_mime_type(filename):
    ext = filename.rsplit('.', 1)[1].lower()
    if ext in ['jpg', 'jpeg']:
        return 'image/jpeg'
    elif ext == 'png':
        return 'image/png'
    elif ext == 'pdf':
        return 'application/pdf'
    return 'application/octet-stream'

@app.route('/healthz', methods=['GET'])
def health():
    """Health check endpoint"""
    return "File Upload Server OK", 200

@app.route('/api/v1/driver/documents', methods=['POST'])
def upload_driver_document():
    """Upload driver document"""
    try:
        # Check if file is present
        if 'document' not in request.files:
            return jsonify({
                "error": "Missing document file"
            }), 400

        file = request.files['document']
        if file.filename == '':
            return jsonify({
                "error": "No file selected"
            }), 400

        # Get additional fields
        document_type = request.form.get('document_type')
        driver_id = request.form.get('driver_id', 'test_driver')

        # Validate document type
        if document_type not in ALLOWED_DOCUMENT_TYPES:
            return jsonify({
                "error": f"Invalid document_type. Must be one of: {', '.join(ALLOWED_DOCUMENT_TYPES)}"
            }), 400

        # Validate file
        if not allowed_file(file.filename):
            return jsonify({
                "error": f"Invalid file type. Only {', '.join(ALLOWED_EXTENSIONS)} allowed"
            }), 400

        # Generate unique filename
        file_id = str(uuid.uuid4())
        original_filename = secure_filename(file.filename)
        file_extension = original_filename.rsplit('.', 1)[1].lower()
        stored_filename = f"{file_id}.{file_extension}"
        file_path = os.path.join(UPLOAD_FOLDER, stored_filename)

        # Save file
        file.save(file_path)
        file_size = os.path.getsize(file_path)

        # Store file info
        file_info = {
            "id": file_id,
            "original_name": original_filename,
            "stored_filename": stored_filename,
            "file_path": file_path,
            "size": file_size,
            "mime_type": get_mime_type(original_filename),
            "document_type": document_type,
            "driver_id": driver_id,
            "created_at": datetime.now().isoformat() + "Z"
        }
        uploaded_files[file_id] = file_info

        print(f"📄 Document uploaded: {original_filename} ({document_type}) for driver {driver_id}")

        return jsonify({
            "id": file_id,
            "original_name": original_filename,
            "public_url": f"http://localhost:5000/api/v1/files/{file_id}",
            "size": file_size,
            "mime_type": get_mime_type(original_filename),
            "created_at": file_info["created_at"]
        }), 200

    except Exception as e:
        return jsonify({
            "error": "Upload failed",
            "message": str(e)
        }), 500

@app.route('/api/v1/orders/<order_id>/photos', methods=['POST'])
def upload_order_photo(order_id):
    """Upload order photo"""
    try:
        # Check if file is present
        if 'photo' not in request.files:
            return jsonify({
                "error": "Missing photo file"
            }), 400

        file = request.files['photo']
        if file.filename == '':
            return jsonify({
                "error": "No file selected"
            }), 400

        # Get photo type
        photo_type = request.form.get('photo_type')

        # Validate photo type
        if photo_type not in ALLOWED_PHOTO_TYPES:
            return jsonify({
                "error": f"Invalid photo_type. Must be one of: {', '.join(ALLOWED_PHOTO_TYPES)}"
            }), 400

        # Validate file (only images for photos)
        if not allowed_file(file.filename) or file.filename.rsplit('.', 1)[1].lower() == 'pdf':
            return jsonify({
                "error": "Invalid file type. Only jpg, png allowed for photos"
            }), 400

        # Generate unique filename
        file_id = str(uuid.uuid4())
        original_filename = secure_filename(file.filename)
        file_extension = original_filename.rsplit('.', 1)[1].lower()
        stored_filename = f"{file_id}.{file_extension}"
        file_path = os.path.join(UPLOAD_FOLDER, stored_filename)

        # Save file
        file.save(file_path)
        file_size = os.path.getsize(file_path)

        # Store file info
        file_info = {
            "id": file_id,
            "original_name": original_filename,
            "stored_filename": stored_filename,
            "file_path": file_path,
            "size": file_size,
            "mime_type": get_mime_type(original_filename),
            "photo_type": photo_type,
            "order_id": order_id,
            "created_at": datetime.now().isoformat() + "Z"
        }
        uploaded_files[file_id] = file_info

        print(f"📸 Photo uploaded: {original_filename} ({photo_type}) for order {order_id}")

        return jsonify({
            "id": file_id,
            "original_name": original_filename,
            "public_url": f"http://localhost:5000/api/v1/files/{file_id}",
            "size": file_size,
            "mime_type": get_mime_type(original_filename),
            "created_at": file_info["created_at"]
        }), 200

    except Exception as e:
        return jsonify({
            "error": "Upload failed",
            "message": str(e)
        }), 500

@app.route('/api/v1/files/<file_id>', methods=['GET'])
def serve_file(file_id):
    """Serve uploaded file"""
    try:
        if file_id not in uploaded_files:
            return jsonify({
                "error": "File not found"
            }), 404

        file_info = uploaded_files[file_id]
        file_path = file_info["file_path"]

        if not os.path.exists(file_path):
            return jsonify({
                "error": "File not found on disk"
            }), 404

        return send_file(
            file_path,
            mimetype=file_info["mime_type"],
            as_attachment=False,
            download_name=file_info["original_name"]
        )

    except Exception as e:
        return jsonify({
            "error": "Failed to serve file",
            "message": str(e)
        }), 500

@app.route('/api/v1/files', methods=['GET'])
def list_files():
    """List all uploaded files (for debugging)"""
    files_list = []
    for file_id, file_info in uploaded_files.items():
        files_list.append({
            "id": file_id,
            "original_name": file_info["original_name"],
            "size": file_info["size"],
            "mime_type": file_info["mime_type"],
            "created_at": file_info["created_at"]
        })

    return jsonify({
        "files": files_list,
        "total": len(files_list)
    }), 200

@app.route('/api/v1/driver/<driver_id>/documents', methods=['GET'])
def get_driver_documents(driver_id):
    """Get all documents for a specific driver"""
    driver_files = []
    for file_id, file_info in uploaded_files.items():
        if file_info.get('driver_id') == driver_id:
            driver_files.append({
                "id": file_id,
                "original_name": file_info["original_name"],
                "document_type": file_info.get("document_type"),
                "size": file_info["size"],
                "mime_type": file_info["mime_type"],
                "public_url": f"http://localhost:5000/api/v1/files/{file_id}",
                "created_at": file_info["created_at"]
            })

    return jsonify({
        "driver_id": driver_id,
        "documents": driver_files,
        "total": len(driver_files)
    }), 200

@app.route('/api/v1/orders/<order_id>/photos', methods=['GET'])
def get_order_photos(order_id):
    """Get all photos for a specific order"""
    order_files = []
    for file_id, file_info in uploaded_files.items():
        if file_info.get('order_id') == order_id:
            order_files.append({
                "id": file_id,
                "original_name": file_info["original_name"],
                "photo_type": file_info.get("photo_type"),
                "size": file_info["size"],
                "mime_type": file_info["mime_type"],
                "public_url": f"http://localhost:5000/api/v1/files/{file_id}",
                "created_at": file_info["created_at"]
            })

    return jsonify({
        "order_id": order_id,
        "photos": order_files,
        "total": len(order_files)
    }), 200

if __name__ == '__main__':
    print("🚀 Mock File Upload Server starting on :5000")
    print("📁 Upload folder:", UPLOAD_FOLDER)
    print("📋 Endpoints:")
    print("   POST /api/v1/driver/documents")
    print("   GET  /api/v1/driver/{id}/documents")
    print("   POST /api/v1/orders/{id}/photos")
    print("   GET  /api/v1/orders/{id}/photos")
    print("   GET  /api/v1/files/{id}")
    print("   GET  /api/v1/files (list all)")
    print("✅ Ready for Flutter file upload testing!")
    print()
    print("📱 Test with Flutter:")
    print("   1. Update ApiClient baseUrl to 'http://localhost:5000/api/v1'")
    print("   2. Use FileUploadService.uploadDriverDocument()")
    print("   3. Check uploads/ folder for saved files")

    app.run(host='0.0.0.0', port=5000, debug=True)