@echo off
title Gemini Web GUI

echo Starting Gemini Web GUI...
echo Backend: http://localhost:3002
echo Frontend: http://localhost:3000 (or 3001 if 3000 is busy)
echo.

:: Check if a starting directory was provided as an argument
if not "%~1"=="" (
    if exist "%~1" (
        set "GEMINI_START_DIR=%~1"
        echo Starting directory set to: %~1
    ) else (
        echo Warning: Provided directory "%~1" does not exist
        echo Will use default starting directory
    )
)

echo Cleaning up any previous runs...
:: Use selective cleanup instead of killing all Node.js processes
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":3000 " 2^>nul') do (
    echo Stopping process on port 3000...
    taskkill /f /pid %%a 2>nul
)
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":3001 " 2^>nul') do (
    echo Stopping process on port 3001...
    taskkill /f /pid %%a 2>nul
)
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":3002 " 2^>nul') do (
    echo Stopping process on port 3002...
    taskkill /f /pid %%a 2>nul
)
timeout /t 1 /nobreak >nul

echo Detecting project directory...
set "SCRIPT_DIR=%~dp0"
set "CURRENT_DIR=%CD%"

:: Check if we're already in the web-gui directory
if exist "package.json" if exist "server.js" (
    echo Found web-gui directory: %CD%
    goto :continue
)

:: Check if we're in the root gemini-gui directory
if exist "packages\web-gui\package.json" (
    cd /d "packages\web-gui"
    echo Navigated to web-gui directory: %CD%
    goto :continue
)

:: Check if the script is in web-gui directory but we're running from elsewhere
if exist "%SCRIPT_DIR%package.json" if exist "%SCRIPT_DIR%server.js" (
    cd /d "%SCRIPT_DIR%"
    echo Navigated to script directory: %CD%
    goto :continue
)

:: Check if we can find the web-gui directory relative to script location
if exist "%SCRIPT_DIR%..\..\packages\web-gui\package.json" (
    cd /d "%SCRIPT_DIR%..\..\packages\web-gui"
    echo Found and navigated to web-gui directory: %CD%
    goto :continue
)

echo Error: Could not find the gemini-gui web-gui directory
echo Script location: %SCRIPT_DIR%
echo Current directory: %CURRENT_DIR%
echo Please ensure this script is in the gemini-gui project
pause
exit /b 1

:continue

echo Installing dependencies if needed...
if not exist "node_modules" (
    echo Installing npm dependencies with --ignore-scripts to bypass build issues...
    npm install --ignore-scripts
    if errorlevel 1 (
        echo Failed to install dependencies
        pause
        exit /b 1
    )
)

echo Starting backend server...
if defined GEMINI_START_DIR (
    start "Backend" cmd /k "cd /d "%CD%" && set GEMINI_START_DIR=%GEMINI_START_DIR% && set PORT=3002 && node "%CD%\server.js""
) else (
    start "Backend" cmd /k "cd /d "%CD%" && set PORT=3002 && node "%CD%\server.js""
)

echo Waiting 5 seconds for backend to initialize...
timeout /t 1 /nobreak >nul

echo Starting frontend server...
start "Frontend" cmd /k "npm run dev"

echo.
echo Both servers are starting in separate windows.
echo Open http://localhost:3000 in your browser!
echo (If port 3000 is busy, frontend will use 3001)
echo Backend API is now on port 3002
echo.
echo Press Ctrl+C in each server window to stop them.
pause
