@echo off
setlocal
cd /d "%~dp0admin-web"
if "%EVIK_API_BASE_URL%"=="" set EVIK_API_BASE_URL=https://tow-truck.onrender.com
if "%ADMIN_WEB_ADDR%"=="" set ADMIN_WEB_ADDR=:5174
rem Optional: set PROMAPS_API_KEY to enable the real ProMaps driver map.
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:5174/admin-api/config' -TimeoutSec 2 | Out-Null; Start-Process 'http://127.0.0.1:5174'; exit 0 } catch { exit 1 }"
if "%ERRORLEVEL%"=="0" exit /b 0
start "" http://127.0.0.1:5174
go run .
