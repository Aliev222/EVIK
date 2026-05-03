# EVIK Admin Web

Separate desktop web console for moderation and operations.

## Run locally

```powershell
cd C:\Users\Minec\Desktop\EVIK\admin-web
$env:EVIK_API_BASE_URL="http://localhost:8080"
$env:YANDEX_MAPS_API_KEY="YOUR_YANDEX_JS_API_KEY"
go run .
```

Open:

```text
http://127.0.0.1:5174
```

## Configuration

Environment variables:

- `ADMIN_WEB_ADDR` - local admin web address, default `:5174`.
- `EVIK_API_BASE_URL` - app backend server URL, default `http://localhost:8080`.
- Backend URL can also be changed in the website settings. The local gateway will proxy requests to that URL.
- `YANDEX_MAPS_API_KEY` - Yandex Maps JavaScript API key for the live driver map. `YANDEX_MAPKIT_API_KEY` is also accepted as a fallback.

The website sends app API calls through the local gateway:

```text
/api/v1/admin/...
```

If the app backend does not yet expose admin endpoints, the website falls back to local mock data and shows `Fallback данные` in the top bar.

## Required production backend endpoints

- `GET /api/v1/admin/overview`
- `GET /api/v1/admin/driver-verifications`
- `POST /api/v1/admin/moderation/driver-verifications/{id}/approve`
- `POST /api/v1/admin/moderation/driver-verifications/{id}/reject`
- `POST /api/v1/admin/moderation/driver-verifications/{id}/request-changes`
- `POST /api/v1/admin/moderation/driver-verifications/{id}/block`
- `GET /api/v1/admin/users`
- `GET /api/v1/admin/reviews`
- `GET /api/v1/admin/drivers-online`

Implemented app-facing data endpoints:

- `POST /api/v1/driver-verifications` - driver submits moderation data.
- `POST /api/v1/reviews` - client submits driver rating and review.

For local development, open `Settings`, click `Войти как admin`, then refresh data. The current backend dev auth issues an admin token for `user_id=admin` and `role=admin`.
