@echo off
title Build Tow Truck Admin
echo.
echo ==========================================
echo   Building Tow Truck Admin Panel
echo ==========================================
echo.

echo Компиляция admin-web.exe...
go build -ldflags="-s -w" -o admin-web.exe .

if %ERRORLEVEL% == 0 (
    echo.
    echo ✅ Сборка завершена успешно!
    echo.
    echo Файл: admin-web.exe
    dir admin-web.exe
    echo.
    echo Для запуска: admin-web.exe
    echo Или: start-production.bat
    echo.
) else (
    echo.
    echo ❌ Ошибка сборки!
    echo.
)

pause