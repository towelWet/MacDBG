@echo off
title Stop Gemini Web GUI

echo Stopping Gemini Web GUI servers...
echo.

echo Looking for running Node.js processes...

:: Get the list of Node.js processes with their window titles
for /f "tokens=2" %%i in ('tasklist /fi "imagename eq node.exe" /fo table /nh 2^>nul') do (
    if not "%%i"=="" (
        echo Found Node.js process with PID: %%i
        
        :: Try to gracefully stop by sending Ctrl+C to specific windows
        echo Attempting graceful shutdown...
        
        :: Send Ctrl+C to Backend window
        powershell -command "try { $proc = Get-Process -Id %%i -ErrorAction Stop; if ($proc.MainWindowTitle -like '*Backend*') { $proc.CloseMainWindow() } } catch { }"
        
        :: Send Ctrl+C to Frontend window  
        powershell -command "try { $proc = Get-Process -Id %%i -ErrorAction Stop; if ($proc.MainWindowTitle -like '*Frontend*') { $proc.CloseMainWindow() } } catch { }"
        
        timeout /t 2 /nobreak >nul
    )
)

echo Waiting 3 seconds for graceful shutdown...
timeout /t 3 /nobreak >nul

:: Check if any Node.js processes are still running
tasklist /fi "imagename eq node.exe" /fo table /nh 2>nul | find "node.exe" >nul
if %errorlevel%==0 (
    echo Some Node.js processes are still running. Forcing termination...
    
    :: Only kill processes on ports 3000, 3001, and 3002 to be more selective
    for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":3000 " 2^>nul') do (
        echo Killing process on port 3000 with PID: %%a
        taskkill /f /pid %%a 2>nul
    )
    
    for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":3001 " 2^>nul') do (
        echo Killing process on port 3001 with PID: %%a
        taskkill /f /pid %%a 2>nul
    )
    
    for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":3002 " 2^>nul') do (
        echo Killing process on port 3002 with PID: %%a
        taskkill /f /pid %%a 2>nul
    )
) else (
    echo All servers stopped successfully.
)

echo.
echo Gemini Web GUI servers have been stopped.
echo You can now safely close this window.
pause
