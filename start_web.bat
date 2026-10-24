@echo off
title LuTrike Web Launcher
cd /d "%~dp0"
echo Starting LuTrike with Supabase connection...
flutter run -d chrome --dart-define-from-file=env.json
pause
