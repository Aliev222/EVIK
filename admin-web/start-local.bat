@echo off
title Tow Truck Admin Server (Local Backend)
echo.
echo ==========================================
echo   Tow Truck Admin Panel - LOCAL MODE
echo ==========================================
echo.

REM Установка переменных окружения для локального backend
set ADMIN_WEB_ADDR=:5174
set ADMIN_API_BASE_URL=http://localhost:8080

echo Запуск admin-web сервера (локальный backend)...
echo.
echo Backend API: %ADMIN_API_BASE_URL%
echo Admin URL:   http://localhost:5174
echo.
echo ВНИМАНИЕ: Убедитесь что backend запущен на порту 8080!
echo Команда для backend: cd ../backend && go run cmd/app/main.go
echo.
echo Для остановки нажмите Ctrl+C
echo ==========================================
echo.

REM Запуск Go сервера
go run main.go

pause