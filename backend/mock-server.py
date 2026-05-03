#!/usr/bin/env python3
"""
Simple Mock Auth Server for EVIK Testing
Replaces Go backend for quick Flutter integration testing
"""

from flask import Flask, jsonify, request
from flask_cors import CORS
import uuid
import time
from datetime import datetime, timedelta

app = Flask(__name__)
CORS(app)  # Allow all origins for testing

# In-memory storage
verification_codes = {}

@app.route('/healthz', methods=['GET'])
def health():
    """Health check endpoint"""
    return "OK", 200

@app.route('/api/v1/auth/send-sms', methods=['POST'])
def send_sms():
    """Send SMS verification code"""
    try:
        data = request.get_json()
        phone = data.get('phone')

        if not phone:
            return jsonify({
                "error": "missing_phone",
                "message": "Phone number is required"
            }), 400

        # Generate verification ID and store code
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
        return jsonify({
            "error": "server_error",
            "message": str(e)
        }), 500

@app.route('/api/v1/auth/verify-sms', methods=['POST'])
def verify_sms():
    """Verify SMS code and return JWT tokens"""
    try:
        data = request.get_json()
        verification_id = data.get('verification_id')
        code = data.get('code')
        phone = data.get('phone')

        if not all([verification_id, code, phone]):
            return jsonify({
                "error": "missing_fields",
                "message": "Missing required fields"
            }), 400

        # Check verification code
        verify_data = verification_codes.get(verification_id)
        if not verify_data:
            return jsonify({
                "error": "invalid_verification_id",
                "message": "Invalid or expired verification ID"
            }), 400

        # Check expiration
        if datetime.now() > verify_data['expires_at']:
            del verification_codes[verification_id]
            return jsonify({
                "error": "expired_code",
                "message": "Verification code expired"
            }), 400

        # Check code
        if verify_data['code'] != code:
            return jsonify({
                "error": "invalid_code",
                "message": "Invalid verification code"
            }), 400

        # Check phone match
        if verify_data['phone'] != phone:
            return jsonify({
                "error": "phone_mismatch",
                "message": "Phone number mismatch"
            }), 400

        # Delete used verification code
        del verification_codes[verification_id]

        # Generate mock tokens
        user_id = f"user_{phone[2:]}"  # Remove +7 prefix
        expires_at = datetime.now() + timedelta(hours=1)

        print(f"✅ User authenticated: {phone} (ID: {user_id})")

        return jsonify({
            "access_token": f"mock_access_token_{user_id}_{int(time.time())}",
            "refresh_token": f"mock_refresh_token_{user_id}_{int(time.time())}",
            "expires_at": expires_at.isoformat() + "Z",
            "user": {
                "id": user_id,
                "phone": phone,
                "role": "client"
            }
        }), 200

    except Exception as e:
        return jsonify({
            "error": "server_error",
            "message": str(e)
        }), 500

@app.route('/api/v1/auth/refresh', methods=['POST'])
def refresh_token():
    """Refresh JWT tokens"""
    try:
        data = request.get_json()
        refresh_token = data.get('refresh_token')

        if not refresh_token:
            return jsonify({
                "error": "missing_refresh_token",
                "message": "Refresh token is required"
            }), 400

        # Mock refresh (in real implementation would validate token)
        expires_at = datetime.now() + timedelta(hours=1)
        user_id = "user_mock"

        return jsonify({
            "access_token": f"mock_access_token_{user_id}_{int(time.time())}",
            "refresh_token": f"mock_refresh_token_{user_id}_{int(time.time())}",
            "expires_at": expires_at.isoformat() + "Z"
        }), 200

    except Exception as e:
        return jsonify({
            "error": "server_error",
            "message": str(e)
        }), 500

if __name__ == '__main__':
    print("🚀 Mock Auth Server starting on :5000")
    print("📱 Test phone: +79123456789")
    print("🔢 Test code: 1234")
    print("✅ Ready for Flutter testing!")

    app.run(host='0.0.0.0', port=5000, debug=True)