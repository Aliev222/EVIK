@echo off
title Tow Truck Admin Server (Production)
echo.
echo ==========================================
echo   Tow Truck Admin Panel - PRODUCTION
echo ==========================================
echo.

REM Проверка существования исполняемого файла
if not exist admin-web.exe (
    echo ❌ admin-web.exe не найден!
    echo.
    echo Сначала выполните сборку:
    echo   build.bat
    echo.
    pause
    exit /b 1
)

REM Установка переменных окружения
set ADMIN_WEB_ADDR=:5174
set ADMIN_API_BASE_URL=https://tow-truck.onrender.com

echo Запуск admin-web сервера (production build)...
echo.
echo Backend API: %ADMIN_API_BASE_URL%
echo Admin URL:   http://localhost:5174
echo.
echo Версия: production build
echo Для остановки нажмите Ctrl+C
echo ==========================================
echo.

REM Запуск скомпилированного сервера
admin-web.exe

pause