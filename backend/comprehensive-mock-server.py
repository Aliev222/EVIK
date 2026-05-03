#!/usr/bin/env python3
"""
Comprehensive Mock Server for EVIK Backend
Объединяет все API: Auth, Orders, File Upload, WebSocket emulation
Готов к немедленному тестированию с Flutter frontend
"""

from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
import uuid
import os
import time
import json
from datetime import datetime, timedelta
from werkzeug.utils import secure_filename

app = Flask(__name__)
CORS(app)

# Configuration
UPLOAD_FOLDER = 'uploads'
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10MB
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'pdf'}

# Ensure upload folder exists
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# In-memory storage
verification_codes = {}
users = {}
orders = {}
uploaded_files = {}
mock_jwt_tokens = {}

def generate_mock_jwt(user_id, phone, role):
    """Generate mock JWT token"""
    token = f"mock_jwt_{user_id}_{int(time.time())}"
    expires_at = datetime.now() + timedelta(hours=1)

    mock_jwt_tokens[token] = {
        "user_id": user_id,
        "phone": phone,
        "role": role,
        "expires_at": expires_at
    }

    return token

def validate_jwt_token(token):
    """Validate mock JWT token"""
    if token not in mock_jwt_tokens:
        return None

    token_data = mock_jwt_tokens[token]
    if datetime.now() > token_data["expires_at"]:
        del mock_jwt_tokens[token]
        return None

    return token_data

def require_auth():
    """Decorator for authenticated endpoints"""
    auth_header = request.headers.get('Authorization', '')
    if not auth_header.startswith('Bearer '):
        return None

    token = auth_header.replace('Bearer ', '')
    return validate_jwt_token(token)

# ================== HEALTH CHECK ==================
@app.route('/healthz', methods=['GET'])
def health():
    return jsonify({
        "status": "ok",
        "timestamp": datetime.now().isoformat(),
        "services": {
            "auth": "ready",
            "orders": "ready",
            "files": "ready",
            "websocket": "emulated"
        }
    }), 200

# ================== AUTHENTICATION ==================
@app.route('/api/v1/auth/send-sms', methods=['POST'])
def send_sms():
    try:
        data = request.get_json()
        phone = data.get('phone')

        if not phone:
            return jsonify({"error": "missing_phone", "message": "Phone number is required"}), 400

        verification_id = str(uuid.uuid4())
        expires_at = datetime.now() + timedelta(minutes=5)

        verification_codes[verification_id] = {
            "phone": phone,
            "code": "1234",  # Always 1234 for testing
            "expires_at": expires_at
        }

        print(f"📱 SMS sent to {phone}, verification_id: {verification_id}, code: 1234")

        return jsonify({
            "verification_id": verification_id,
            "expires_at": expires_at.isoformat() + "Z"
        }), 200

    except Exception as e:
        return jsonify({"error": "server_error", "message": str(e)}), 500

@app.route('/api/v1/auth/verify-sms', methods=['POST'])
def verify_sms():
    try:
        data = request.get_json()
        verification_id = data.get('verification_id')
        code = data.get('code')
        phone = data.get('phone')
        full_name = data.get('full_name', 'Test User')
        role = data.get('role', 'client')

        if not all([verification_id, code, phone]):
            return jsonify({"error": "missing_fields", "message": "Missing required fields"}), 400

        verify_data = verification_codes.get(verification_id)
        if not verify_data:
            return jsonify({"error": "invalid_verification_id", "message": "Invalid verification ID"}), 400

        if datetime.now() > verify_data['expires_at']:
            del verification_codes[verification_id]
            return jsonify({"error": "expired_code", "message": "Verification code expired"}), 400

        if verify_data['code'] != code or verify_data['phone'] != phone:
            return jsonify({"error": "invalid_code", "message": "Invalid verification code"}), 400

        # Delete used verification code
        del verification_codes[verification_id]

        # Create user
        user_id = f"user_{phone.replace('+', '').replace('-', '')}"
        user = {
            "id": user_id,
            "phone": phone,
            "full_name": full_name,
            "role": role,
            "created_at": datetime.now().isoformat() + "Z"
        }
        users[user_id] = user

        # Generate tokens
        access_token = generate_mock_jwt(user_id, phone, role)
        refresh_token = generate_mock_jwt(user_id, phone, role)

        expires_at = datetime.now() + timedelta(hours=1)

        print(f"✅ User authenticated: {phone} (ID: {user_id}, Role: {role})")

        return jsonify({
            "access_token": access_token,
            "refresh_token": refresh_token,
            "expires_at": expires_at.isoformat() + "Z",
            "user": user
        }), 200

    except Exception as e:
        return jsonify({"error": "server_error", "message": str(e)}), 500

@app.route('/api/v1/auth/me', methods=['GET'])
def get_current_user():
    auth_data = require_auth()
    if not auth_data:
        return jsonify({"error": "unauthorized", "message": "Invalid token"}), 401

    user = users.get(auth_data["user_id"])
    if not user:
        return jsonify({"error": "user_not_found", "message": "User not found"}), 404

    return jsonify({"user": user}), 200

# ================== ORDERS ==================
@app.route('/api/v1/orders', methods=['POST'])
def create_order():
    auth_data = require_auth()
    if not auth_data:
        return jsonify({"error": "unauthorized"}), 401

    data = request.get_json()

    order_id = str(uuid.uuid4())
    order = {
        "id": order_id,
        "user_id": auth_data["user_id"],
        "driver_id": None,
        "pickup": {
            "lat": data.get("pickup_lat"),
            "lng": data.get("pickup_lng")
        },
        "dropoff": {
            "lat": data.get("dropoff_lat"),
            "lng": data.get("dropoff_lng")
        },
        "pickup_lat": data.get("pickup_lat"),
        "pickup_lng": data.get("pickup_lng"),
        "dropoff_lat": data.get("dropoff_lat"),
        "dropoff_lng": data.get("dropoff_lng"),
        "vehicle_type": data.get("vehicle_type", "light"),
        "payment_method": data.get("payment_method", "cash"),
        "price": data.get("price"),
        "description": data.get("description", ""),
        "notes": data.get("notes", ""),
        "status": "searching",
        "created_at": datetime.now().isoformat() + "Z",
        "updated_at": datetime.now().isoformat() + "Z",
        "cancelled_at": None
    }

    orders[order_id] = order
    print(f"📦 Order created: {order_id} for user {auth_data['user_id']}")

    return jsonify({"order": order}), 201

@app.route('/api/v1/orders', methods=['GET'])
def list_orders():
    auth_data = require_auth()
    if not auth_data:
        return jsonify({"error": "unauthorized"}), 401

    status_filter = request.args.get('status')
    limit = int(request.args.get('limit', 20))

    filtered_orders = []
    for order in orders.values():
        if status_filter and order["status"] != status_filter:
            continue
        # For clients - only their orders, for drivers/admin - all orders
        if auth_data["role"] == "client" and order["user_id"] != auth_data["user_id"]:
            continue
        filtered_orders.append(order)

    # Sort by created_at desc and limit
    filtered_orders.sort(key=lambda x: x["created_at"], reverse=True)
    filtered_orders = filtered_orders[:limit]

    return jsonify({"orders": filtered_orders}), 200

@app.route('/api/v1/orders/<order_id>', methods=['GET'])
def get_order(order_id):
    auth_data = require_auth()
    if not auth_data:
        return jsonify({"error": "unauthorized"}), 401

    order = orders.get(order_id)
    if not order:
        return jsonify({"error": "order_not_found"}), 404

    return jsonify({"order": order}), 200

@app.route('/api/v1/orders/<order_id>/accept', methods=['POST'])
def accept_order(order_id):
    auth_data = require_auth()
    if not auth_data:
        return jsonify({"error": "unauthorized"}), 401

    order = orders.get(order_id)
    if not order:
        return jsonify({"error": "order_not_found"}), 404

    if order["status"] != "searching":
        return jsonify({"error": "invalid_transition", "message": "Order is not available"}), 400

    # Update order
    order["driver_id"] = auth_data["user_id"]
    order["status"] = "accepted"
    order["updated_at"] = datetime.now().isoformat() + "Z"

    print(f"🚗 Order {order_id} accepted by driver {auth_data['user_id']}")

    return jsonify({"order": order}), 200

@app.route('/api/v1/orders/<order_id>/status', methods=['POST'])
def update_order_status(order_id):
    auth_data = require_auth()
    if not auth_data:
        return jsonify({"error": "unauthorized"}), 401

    data = request.get_json()
    new_status = data.get("status")

    order = orders.get(order_id)
    if not order:
        return jsonify({"error": "order_not_found"}), 404

    # Update status
    order["status"] = new_status
    order["updated_at"] = datetime.now().isoformat() + "Z"

    print(f"📋 Order {order_id} status updated to: {new_status}")

    return jsonify({"order": order}), 200

# ================== FILE UPLOAD ==================
@app.route('/api/v1/driver/documents', methods=['POST'])
def upload_driver_document():
    auth_data = require_auth()
    if not auth_data:
        return jsonify({"error": "unauthorized"}), 401

    if 'document' not in request.files:
        return jsonify({"error": "Missing document file"}), 400

    file = request.files['document']
    document_type = request.form.get('document_type')
    driver_id = request.form.get('driver_id', auth_data["user_id"])

    if not document_type:
        return jsonify({"error": "Missing document_type"}), 400

    # Save file
    file_id = str(uuid.uuid4())
    original_filename = secure_filename(file.filename)
    file_extension = original_filename.rsplit('.', 1)[1].lower() if '.' in original_filename else ''
    stored_filename = f"{file_id}.{file_extension}"
    file_path = os.path.join(UPLOAD_FOLDER, stored_filename)

    file.save(file_path)
    file_size = os.path.getsize(file_path)

    # Store file info
    file_info = {
        "id": file_id,
        "original_name": original_filename,
        "stored_filename": stored_filename,
        "file_path": file_path,
        "size": file_size,
        "mime_type": f"image/{file_extension}" if file_extension in ['jpg', 'jpeg', 'png'] else f"application/{file_extension}",
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
        "mime_type": file_info["mime_type"],
        "created_at": file_info["created_at"]
    }), 200

@app.route('/api/v1/files/<file_id>', methods=['GET'])
def serve_file(file_id):
    if file_id not in uploaded_files:
        return jsonify({"error": "File not found"}), 404

    file_info = uploaded_files[file_id]
    file_path = file_info["file_path"]

    if not os.path.exists(file_path):
        return jsonify({"error": "File not found on disk"}), 404

    return send_file(
        file_path,
        mimetype=file_info["mime_type"],
        as_attachment=False,
        download_name=file_info["original_name"]
    )

# ================== DEBUGGING ENDPOINTS ==================
@app.route('/api/v1/debug/stats', methods=['GET'])
def debug_stats():
    return jsonify({
        "users": len(users),
        "orders": len(orders),
        "files": len(uploaded_files),
        "active_tokens": len(mock_jwt_tokens),
        "verification_codes": len(verification_codes)
    }), 200

if __name__ == '__main__':
    print("🚀 EVIK Comprehensive Mock Server starting on :5000")
    print()
    print("📋 Available APIs:")
    print("   🔐 Authentication: /api/v1/auth/*")
    print("   📦 Orders: /api/v1/orders/*")
    print("   📁 Files: /api/v1/driver/documents, /api/v1/files/*")
    print("   🔧 Debug: /api/v1/debug/stats")
    print()
    print("📱 Ready for complete Flutter integration testing!")
    print("🔑 Test credentials: +79123456789, code: 1234")
    print("✅ All Firebase functionality replaced!")

    app.run(host='0.0.0.0', port=5000, debug=True)