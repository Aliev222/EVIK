@echo off
title Tow Truck Admin Server
echo.
echo ==========================================
echo   Tow Truck Admin Panel
echo ==========================================
echo.

REM Установка переменных окружения
set ADMIN_WEB_ADDR=:5174
set ADMIN_API_BASE_URL=https://tow-truck.onrender.com

echo Запуск admin-web сервера...
echo.
echo Backend API: %ADMIN_API_BASE_URL%
echo Admin URL:   http://localhost:5174
echo.
echo Для остановки нажмите Ctrl+C
echo ==========================================
echo.

REM Запуск Go сервера
go run main.go

pause