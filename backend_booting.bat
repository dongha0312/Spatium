@echo off
setlocal

set "ROOT_DIR=%~dp0"
set "BACKEND_DIR=%ROOT_DIR%spatium-backend"
set "FRONTEND_DIR=%ROOT_DIR%spatium-frontend"

wt ^
  new-tab --title "frontend start" -d "%FRONTEND_DIR%" cmd /k "npm start"
  ; new-tab --title "backend classes -t" -d "%BACKEND_DIR%" cmd /k ".\gradlew.bat classes -t" ^
  ; new-tab --title "backend bootRun" -d "%BACKEND_DIR%" cmd /k ".\gradlew.bat bootRun" ^