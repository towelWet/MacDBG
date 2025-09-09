@echo off
echo Listing all code files and their contents to listfiles.txt...
(
echo File Listing Start: %date% %time%
echo ================================================

for %%F in (
    "index.html"
    "main.js"
    "package.json"
    "README.md"
    "style.css"
    "CSXS\manifest.xml"
    "host\TowelWebcam.jsx"
) do (
    echo FILE: %%~F
    echo ================================================
    if exist %%F (
        type %%F
    ) else (
        echo File not found: %%F
    )
    echo.
    echo ================================================
    echo.
)

) > listfiles.txt
echo Done! Check listfiles.txt for the complete code listing.
pause