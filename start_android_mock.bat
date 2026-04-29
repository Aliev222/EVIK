@echo off
echo 🤖 Запуск EVIK на Android эмуляторе с мок-данными...
echo.
echo ⚠️ Убедитесь что Android эмулятор запущен!
echo.
echo 🧪 Мок-режим: Любой 6-значный код = успешный вход
echo Например: 123456, 999999, 111111, 222222
echo.
pause
echo.
echo 🚀 Запускаем приложение...

cd frontend

flutter run --dart-define=USE_MOCK_DATA=true -d android

pause