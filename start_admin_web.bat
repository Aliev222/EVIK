@echo off
setlocal
cd /d "%~dp0admin-web"
if "%EVIK_API_BASE_URL%"=="" set EVIK_API_BASE_URL=http://localhost:8080
if "%ADMIN_WEB_ADDR%"=="" set ADMIN_WEB_ADDR=:5174
rem Optional: set YANDEX_MAPS_API_KEY to enable the real Yandex driver map.
go run .
