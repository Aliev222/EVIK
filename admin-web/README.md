# EVIK Admin Web

Separate desktop web console for moderation and operations.

## Run Locally With Render

```powershell
cd C:\Users\Minec\Desktop\EVIK-main-build
.\start_admin_web.bat
```

Open:

```text
http://127.0.0.1:5174
```

The launcher connects the local admin gateway to:

```text
https://tow-truck.onrender.com
```

Manual run:

```powershell
cd C:\Users\Minec\Desktop\EVIK-main-build\admin-web
$env:EVIK_API_BASE_URL="https://tow-truck.onrender.com"
$env:PROMAPS_API_KEY="YOUR_PROMAPS_API_KEY"
go run .
```

## Configuration

- `ADMIN_WEB_ADDR` - local admin web address, default `:5174`.
- `EVIK_API_BASE_URL` - app backend server URL, default `https://tow-truck.onrender.com`.
- `PROMAPS_API_KEY` - ProMaps API key for the live driver map.

The website sends app API calls through the local gateway:

```text
/api/v1/admin/...
```

If the app backend or admin token is unavailable, the website shows an API error state instead of fake production values.

## Required Backend Endpoints

- `GET /api/v1/admin/overview`
- `GET /api/v1/admin/driver-verifications`
- `POST /api/v1/admin/moderation/driver-verifications/{id}/approve`
- `POST /api/v1/admin/moderation/driver-verifications/{id}/reject`
- `POST /api/v1/admin/moderation/driver-verifications/{id}/request-changes`
- `POST /api/v1/admin/moderation/driver-verifications/{id}/block`
- `GET /api/v1/admin/users`
- `GET /api/v1/admin/reviews`
- `GET /api/v1/admin/drivers-online`

For local development, open `Settings`, enter the Render `ADMIN_PASSWORD`, click `Войти как admin`, then refresh data.
