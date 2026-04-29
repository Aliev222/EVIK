@echo off
echo 🚀 Запуск Tow Truck для тестирования нового splash screen
echo ✨ Новые фишки:
echo   - Чистый оранжевый логотип мигалки (без фона)
echo   - Крупный размер 240x240px
echo   - Название "TOW TRUCK"
echo   - Анимация мигания
echo   - Двойное оранжевое свечение (близкое + дальнее)
echo.
echo Выберите платформу:
echo 1. Веб (Chrome)
echo 2. Android
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
    echo 🖥️ Запуск Windows...
    flutter run -d windows --dart-define=SKIP_AUTH=true
) else (
    echo ❌ Неверный выбор
    pause
)

pause