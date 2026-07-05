@echo off
echo 🚀 Запуск EVIK с реальным API...
echo.
echo Выберите платформу:
echo 1. Веб (Chrome)
echo 2. Windows
echo 3. Отмена
echo.
set /p choice="Введите номер (1-3): "

cd frontend

if "%choice%"=="1" (
    echo 🌐 Запуск веб версии...
    flutter run -d chrome --web-port 3000
) else if "%choice%"=="2" (
    echo 🖥️ Запуск Windows версии...
    flutter run -d windows
) else if "%choice%"=="3" (
    echo 🚫 Отменено пользователем
    exit /b 0
) else (
    echo ❌ Неверный выбор
    pause
)

pause
