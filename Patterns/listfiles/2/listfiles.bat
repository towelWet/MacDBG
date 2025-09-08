@echo off
title Generate Code Listing

echo Generating code listing for Web-GUI project...
echo This will create listfiles.txt with all code contents
echo.

set "OUTPUT_FILE=listfiles.txt"

:: Clear the output file
echo Web-GUI Project Complete Code Listing > "%OUTPUT_FILE%"
echo Generated on %DATE% at %TIME% >> "%OUTPUT_FILE%"
echo ======================================== >> "%OUTPUT_FILE%"
echo. >> "%OUTPUT_FILE%"

:: Function to add file content
setlocal enabledelayedexpansion

:: MAIN SERVER FILE
echo ======================================== >> "%OUTPUT_FILE%"
echo SERVER >> "%OUTPUT_FILE%"
echo ======================================== >> "%OUTPUT_FILE%"
echo. >> "%OUTPUT_FILE%"

for %%f in (server.js) do (
    if exist "%%f" (
        echo ---------------------------------------- >> "%OUTPUT_FILE%"
        echo FILE: %%f >> "%OUTPUT_FILE%"
        echo ---------------------------------------- >> "%OUTPUT_FILE%"
        type "%%f" >> "%OUTPUT_FILE%"
        echo. >> "%OUTPUT_FILE%"
        echo. >> "%OUTPUT_FILE%"
    )
)

:: MAIN SOURCE FILES
echo ======================================== >> "%OUTPUT_FILE%"
echo MAIN SOURCE FILES >> "%OUTPUT_FILE%"
echo ======================================== >> "%OUTPUT_FILE%"
echo. >> "%OUTPUT_FILE%"

for %%f in (src\main.tsx src\App.tsx src\App_backup.tsx src\index.css src\server.ts) do (
    if exist "%%f" (
        echo ---------------------------------------- >> "%OUTPUT_FILE%"
        echo FILE: %%f >> "%OUTPUT_FILE%"
        echo ---------------------------------------- >> "%OUTPUT_FILE%"
        type "%%f" >> "%OUTPUT_FILE%"
        echo. >> "%OUTPUT_FILE%"
        echo. >> "%OUTPUT_FILE%"
    )
)

:: SERVICES
echo ======================================== >> "%OUTPUT_FILE%"
echo SERVICES >> "%OUTPUT_FILE%"
echo ======================================== >> "%OUTPUT_FILE%"
echo. >> "%OUTPUT_FILE%"

for %%f in (src\services\*.ts src\services\*.tsx) do (
    if exist "%%f" (
        echo ---------------------------------------- >> "%OUTPUT_FILE%"
        echo FILE: %%f >> "%OUTPUT_FILE%"
        echo ---------------------------------------- >> "%OUTPUT_FILE%"
        type "%%f" >> "%OUTPUT_FILE%"
        echo. >> "%OUTPUT_FILE%"
        echo. >> "%OUTPUT_FILE%"
    )
)

:: CONTEXT PROVIDERS
echo ======================================== >> "%OUTPUT_FILE%"
echo CONTEXT PROVIDERS >> "%OUTPUT_FILE%"
echo ======================================== >> "%OUTPUT_FILE%"
echo. >> "%OUTPUT_FILE%"

for %%f in (src\context\*.tsx src\context\*.ts) do (
    if exist "%%f" (
        echo ---------------------------------------- >> "%OUTPUT_FILE%"
        echo FILE: %%f >> "%OUTPUT_FILE%"
        echo ---------------------------------------- >> "%OUTPUT_FILE%"
        type "%%f" >> "%OUTPUT_FILE%"
        echo. >> "%OUTPUT_FILE%"
        echo. >> "%OUTPUT_FILE%"
    )
)

:: COMPONENTS
echo ======================================== >> "%OUTPUT_FILE%"
echo COMPONENTS >> "%OUTPUT_FILE%"
echo ======================================== >> "%OUTPUT_FILE%"
echo. >> "%OUTPUT_FILE%"

for %%f in (src\components\*.tsx src\components\*.ts) do (
    if exist "%%f" (
        echo ---------------------------------------- >> "%OUTPUT_FILE%"
        echo FILE: %%f >> "%OUTPUT_FILE%"
        echo ---------------------------------------- >> "%OUTPUT_FILE%"
        type "%%f" >> "%OUTPUT_FILE%"
        echo. >> "%OUTPUT_FILE%"
        echo. >> "%OUTPUT_FILE%"
    )
)

:: PAGES
echo ======================================== >> "%OUTPUT_FILE%"
echo PAGES >> "%OUTPUT_FILE%"
echo ======================================== >> "%OUTPUT_FILE%"
echo. >> "%OUTPUT_FILE%"

for %%f in (src\pages\*.tsx src\pages\*.ts) do (
    if exist "%%f" (
        echo ---------------------------------------- >> "%OUTPUT_FILE%"
        echo FILE: %%f >> "%OUTPUT_FILE%"
        echo ---------------------------------------- >> "%OUTPUT_FILE%"
        type "%%f" >> "%OUTPUT_FILE%"
        echo. >> "%OUTPUT_FILE%"
        echo. >> "%OUTPUT_FILE%"
    )
)

:: Add file summary at the end
echo ======================================== >> "%OUTPUT_FILE%"
echo FILE SUMMARY >> "%OUTPUT_FILE%"
echo ======================================== >> "%OUTPUT_FILE%"
echo. >> "%OUTPUT_FILE%"
echo Total files processed: >> "%OUTPUT_FILE%"

:: Count and list all files
set /a filecount=0
for %%f in (server.js) do (
    if exist "%%f" (
        set /a filecount+=1
        echo - %%f >> "%OUTPUT_FILE%"
    )
)

for %%f in (src\main.tsx src\App.tsx src\App_backup.tsx src\index.css src\server.ts) do (
    if exist "%%f" (
        set /a filecount+=1
        echo - %%f >> "%OUTPUT_FILE%"
    )
)

for %%f in (src\services\*.ts src\services\*.tsx) do (
    if exist "%%f" (
        set /a filecount+=1
        echo - %%f >> "%OUTPUT_FILE%"
    )
)

for %%f in (src\context\*.tsx src\context\*.ts) do (
    if exist "%%f" (
        set /a filecount+=1
        echo - %%f >> "%OUTPUT_FILE%"
    )
)

for %%f in (src\components\*.tsx src\components\*.ts) do (
    if exist "%%f" (
        set /a filecount+=1
        echo - %%f >> "%OUTPUT_FILE%"
    )
)

for %%f in (src\pages\*.tsx src\pages\*.ts) do (
    if exist "%%f" (
        set /a filecount+=1
        echo - %%f >> "%OUTPUT_FILE%"
    )
)

echo. >> "%OUTPUT_FILE%"
echo Total: !filecount! files >> "%OUTPUT_FILE%"
echo Generated on %DATE% at %TIME% >> "%OUTPUT_FILE%"

echo.
echo ✅ Code listing generated successfully!
echo 📄 Output saved to: %OUTPUT_FILE%
echo 📊 Total files: !filecount!
echo.
echo You can now open %OUTPUT_FILE% to view all code contents.
pause
