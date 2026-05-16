@echo off
echo 🚀 Запуск EVIK с реальным API...
echo.
echo ⚠️ ВНИМАНИЕ: Подключение к продакшн бэкенду!
echo API: https://tow-truck.onrender.com
echo.
echo Выберите платформу:
echo 1. Веб (Chrome)
echo 2. Windows
echo 3. Отмена
echo.
set /p choice="Введите номер (1-3): "

cd frontend

if "%choice%"=="1" (
    echo 🌐 Запуск веб версии с реальным API...
    flutter run -d chrome --web-port 3000 --dart-define=USE_MOCK_DATA=false
) else if "%choice%"=="2" (
    echo 🖥️ Запуск Windows версии с реальным API...
    flutter run -d windows --dart-define=USE_MOCK_DATA=false
) else if "%choice%"=="3" (
    echo 🚫 Отменено пользователем
    exit /b 0
) else (
    echo ❌ Неверный выбор
    pause
)

pause
