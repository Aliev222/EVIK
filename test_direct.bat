@echo off
echo 🚀 Запуск EVIK в режиме прямого тестирования
echo ✅ Пропуск авторизации - сразу выбор роли
echo.
echo Выберите платформу:
echo 1. Веб (Chrome)
echo 2. Android (эмулятор)
echo 3. Windows
echo.
set /p choice="Введите номер (1-3): "

cd frontend

if "%choice%"=="1" (
    echo 🌐 Запуск в браузере...
    flutter run -d chrome --web-port 3000 --dart-define=SKIP_AUTH=true
) else if "%choice%"=="2" (
    echo 🤖 Запуск на Android...
    flutter run -d android --dart-define=SKIP_AUTH=true
) else if "%choice%"=="3" (
    echo 🖥️ Запуск Windows приложения...
    flutter run -d windows --dart-define=SKIP_AUTH=true
) else (
    echo ❌ Неверный выбор
    pause
)

pause