# EVIK Production Deploy On Timeweb Cloud

## Recommended Layout

- `api.your-domain.ru` -> Go backend
- `admin.your-domain.ru` -> admin web
- PostgreSQL and Redis stay inside the Docker network, no public ports.
- HTTPS terminates at Nginx.
- Driver documents should be stored in Timeweb S3.

## First Setup

1. Copy env:

```powershell
cd C:\Users\Minec\Desktop\EVIK\deploy
Copy-Item .env.prod.example .env.prod
```

2. Edit `.env.prod`:

- Replace all `CHANGE_ME...`
- Set real domains in `ALLOWED_ORIGINS`
- Set `YANDEX_MAPS_API_KEY`
- Set S3 credentials

3. Copy Nginx config:

```powershell
Copy-Item .\nginx\conf.d\evik.conf.example .\nginx\conf.d\evik.conf
```

Replace:

- `api.example.ru`
- `admin.example.ru`

4. Start services:

```powershell
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build
```

5. Issue HTTPS certificates on the server with certbot, then restart Nginx.

## Backups

Run manually:

```powershell
.\backup-postgres.ps1
```

On Linux server, create a cron job with the equivalent `pg_dump | gzip` command.

## Security Checklist

- `APP_ENV=production`
- Strong `JWT_SECRET`
- Strong `ADMIN_PASSWORD`
- Redis/Postgres ports are not exposed publicly
- `ALLOWED_ORIGINS` contains only production domains
- HTTPS certificates installed
- S3 bucket created and credentials set
- Backups scheduled and restore tested

