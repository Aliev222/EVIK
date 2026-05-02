param(
  [string]$ComposeFile = ".\docker-compose.prod.yml",
  [string]$EnvFile = ".\.env.prod"
)

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $PSScriptRoot "backups"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$backupFile = "/backups/evik-$timestamp.sql.gz"

docker compose --env-file $EnvFile -f $ComposeFile exec -T postgres sh -c "pg_dump -U `$POSTGRES_USER `$POSTGRES_DB | gzip > $backupFile"
Write-Host "Backup created: $backupFile"

