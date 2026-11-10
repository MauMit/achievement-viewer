@echo off
setlocal EnableDelayedExpansion

REM ============================================
REM Achievement Viewer - GSE + Goldberg Sync
REM ============================================

set "GSE=%APPDATA%\GSE Saves"
set "GOLDBERG=%APPDATA%\Goldberg SteamEmu Saves"

REM Repo folder: pass it as the first argument, or edit the default below.
REM It must be a local clone of this repo on the "user" branch.
set "REPO=%USERPROFILE%\Desktop\Egna Projekt\achievement-viewer\achievement-viewer"
if not "%~1"=="" set "REPO=%~1"

echo.
echo ============================================
echo   Achievement Viewer Sync
echo ============================================
echo.

cd /d "%REPO%"

REM Make sure we're on the user branch
git checkout user
if errorlevel 1 goto ERROR

REM Get latest changes
git pull origin user
if errorlevel 1 goto ERROR


REM ============================================
REM GSE FORK
REM ============================================

echo.
echo --------------------------------------------
echo   Scanning GSE Saves
echo --------------------------------------------

if exist "%GSE%" (
    for /d %%D in ("%GSE%\*") do (
        set "APPID=%%~nxD"

        if exist "%%D\achievements.json" (
            echo [GSE] !APPID!

            if not exist "%REPO%\AppID\!APPID!" (
                mkdir "%REPO%\AppID\!APPID!"
            )

            copy /Y "%%D\achievements.json" "%REPO%\AppID\!APPID!\achievements.json" >nul
        )
    )
) else (
    echo GSE Saves folder not found.
)


REM ============================================
REM CLASSIC GOLDBERG
REM ============================================

echo.
echo --------------------------------------------
echo   Scanning Goldberg SteamEmu Saves
echo --------------------------------------------

if exist "%GOLDBERG%" (
    for /d %%D in ("%GOLDBERG%\*") do (
        set "APPID=%%~nxD"

        if exist "%%D\achievements.json" (
            echo [Goldberg] !APPID!

            if not exist "%REPO%\AppID\!APPID!" (
                mkdir "%REPO%\AppID\!APPID!"
            )

            copy /Y "%%D\achievements.json" "%REPO%\AppID\!APPID!\achievements.json" >nul
        )
    )
) else (
    echo Goldberg SteamEmu Saves folder not found.
)


REM ============================================
REM GIT
REM ============================================

echo.
echo ============================================
echo   Checking for changes
echo ============================================
echo.

git add AppID

git diff --cached --quiet

if %ERRORLEVEL% EQU 0 (
    echo No achievement changes found.
    echo Everything is already up to date.
    goto END
)

echo Changes found:
git status --short

echo.
echo Committing...
git commit -m "Sync GSE and Goldberg achievements"
if errorlevel 1 goto ERROR

echo.
echo Uploading to GitHub...
git push origin user
if errorlevel 1 goto ERROR

echo.
echo ============================================
echo   Achievement sync complete!
echo ============================================
goto END


:ERROR
echo.
echo ============================================
echo   ERROR - Sync failed!
echo ============================================
echo.
echo Check the error above.

:END
echo.
pause