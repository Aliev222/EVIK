@echo off
title Full Local Tow Truck Setup
echo.
echo ==========================================
echo   FULL LOCAL SETUP - Tow Truck
echo ==========================================
echo.

REM Проверка Go
where go >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ❌ Go не найден! Установите Go с https://golang.org/dl/
    pause
    exit /b 1
)

echo Запуск backend + admin-web локально...
echo.
echo ⚠️  ВНИМАНИЕ: Откроются 2 окна терминала:
echo    1. Backend server (порт 8080)
echo    2. Admin-web server (порт 5174)
echo.
echo 📋 После запуска:
echo    - Backend API: http://localhost:8080
echo    - Admin Panel: http://localhost:5174
echo    - Логин: admin, Пароль: [ваш admin пароль]
echo.
echo Для остановки закройте оба окна терминала
echo ==========================================
echo.

REM Запуск backend в новом окне
start "Tow Truck Backend" cmd /c "cd backend && echo Запуск backend server... && go run cmd/app/main.go && pause"

REM Небольшая пауза чтобы backend успел запуститься
timeout /t 3 /nobreak >nul

REM Запуск admin-web в новом окне
start "Tow Truck Admin" cmd /c "cd admin-web && echo Запуск admin-web server... && set ADMIN_API_BASE_URL=http://localhost:8080 && go run main.go && pause"

echo.
echo ✅ Серверы запускаются...
echo.
echo Через несколько секунд откройте:
echo http://localhost:5174
echo.

pause