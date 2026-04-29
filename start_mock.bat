@echo off
echo 🧪 Запуск EVIK в мок-режиме для тестирования...
echo.
echo Выберите платформу:
echo 1. Веб (Chrome)
echo 2. Windows
echo 3. Анализ кода
echo.
set /p choice="Введите номер (1-3): "

cd frontend

if "%choice%"=="1" (
    echo 🌐 Запуск веб версии с мок-данными...
    flutter run -d chrome --web-port 3000 --dart-define=USE_MOCK_DATA=true
) else if "%choice%"=="2" (
    echo 🖥️ Запуск Windows версии с мок-данными...
    flutter run -d windows --dart-define=USE_MOCK_DATA=true
) else if "%choice%"=="3" (
    echo 🔍 Анализ кода...
    flutter analyze --fatal-infos
) else (
    echo ❌ Неверный выбор
    pause
)

pause