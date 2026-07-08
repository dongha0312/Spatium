@echo off
setlocal

set "BACKEND_DIR=%~dp0spatium-backend"

wt ^
  new-tab --title "classes -t" -d "%BACKEND_DIR%" cmd /k ".\gradlew.bat classes -t" ^
  ; new-tab --title "bootRun" -d "%BACKEND_DIR%" cmd /k ".\gradlew.bat bootRun"