@echo off
title Check Backend Status
echo.
echo ==========================================
echo   Проверка статуса Backend
echo ==========================================
echo.

echo Проверяем production backend...
echo URL: https://tow-truck.onrender.com/healthz
echo.

REM Проверка через curl (если установлен)
where curl >nul 2>&1
if %ERRORLEVEL% == 0 (
    echo Используем curl...
    curl -s https://tow-truck.onrender.com/healthz
    echo.
    if %ERRORLEVEL% == 0 (
        echo ✅ Backend отвечает!
    ) else (
        echo ❌ Backend недоступен
    )
) else (
    echo curl не найден, используем PowerShell...
    powershell -Command "try { $response = Invoke-WebRequest -Uri 'https://tow-truck.onrender.com/healthz' -UseBasicParsing; Write-Host '✅ Backend отвечает! Status:' $response.StatusCode } catch { Write-Host '❌ Backend недоступен:' $_.Exception.Message }"
)

echo.
echo Проверяем локальный backend...
echo URL: http://localhost:8080/healthz
echo.

if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    powershell -Command "try { $response = Invoke-WebRequest -Uri 'http://localhost:8080/healthz' -UseBasicParsing -TimeoutSec 3; Write-Host '✅ Локальный backend работает! Status:' $response.StatusCode } catch { Write-Host '❌ Локальный backend недоступен (это нормально, если не запущен)' }"
) else (
    echo PowerShell недоступен для проверки локального backend
)

echo.
echo ==========================================
echo Рекомендации:
echo.
echo 1. Если production backend недоступен:
echo    - Он может "спать" на Render.com
echo    - Откройте https://tow-truck.onrender.com/healthz в браузере
echo    - Подождите 1-2 минуты пока проснется
echo.
echo 2. Если хотите локальный backend:
echo    cd ../backend
echo    go run cmd/app/main.go
echo.
echo 3. Затем запустите админку:
echo    start.bat (для production backend)
echo    start-local.bat (для локального backend)
echo ==========================================

pause