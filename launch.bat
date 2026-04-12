@echo off
rem Perce-Neige Simulator launcher (Windows).
rem Venv lives at %USERPROFILE%\.perce_neige_sim\venv — a non-virtualized
rem location that every Python (real or Store) can safely write to, and
rem that stays local to each PC (never inside the project folder which is
rem NAS-synced).

setlocal enabledelayedexpansion
set "APP=PerceNeigeSim"
set "PROJ=%~dp0"
set "VENVROOT=%USERPROFILE%\.perce_neige_sim"
set "VENVDIR=%VENVROOT%\venv"
set "PY="

rem --------------------------------------------------------------------------
rem Detect a REAL Python 3 runtime.
rem
rem Strategy : look in standard install locations first (python.org / winget
rem installs drop python.exe under %LOCALAPPDATA%\Programs\Python\Python3XX).
rem The %PATH% stubs %LOCALAPPDATA%\Microsoft\WindowsApps\python.exe are the
rem Microsoft Store redirectors — they DO work to run Python but require the
rem venv to live outside virtualized folders. We still accept them as a last
rem resort since we already use a non-virtualized venv path.
rem --------------------------------------------------------------------------
for %%V in (313 312 311 310 39) do (
    if not defined PY (
        if exist "%LOCALAPPDATA%\Programs\Python\Python%%V\python.exe" (
            set "PY=%LOCALAPPDATA%\Programs\Python\Python%%V\python.exe"
        )
    )
)
for %%V in (313 312 311 310 39) do (
    if not defined PY (
        if exist "C:\Python%%V\python.exe" (
            set "PY=C:\Python%%V\python.exe"
        )
    )
)
for %%V in (313 312 311 310 39) do (
    if not defined PY (
        if exist "C:\Program Files\Python%%V\python.exe" (
            set "PY=C:\Program Files\Python%%V\python.exe"
        )
    )
)
rem Try PATH commands as a last resort (Store stubs are OK here).
if not defined PY (
    py -3 --version >nul 2>&1
    if !errorlevel! equ 0 set "PY=py -3"
)
if not defined PY (
    python --version >nul 2>&1
    if !errorlevel! equ 0 set "PY=python"
)
if not defined PY (
    python3 --version >nul 2>&1
    if !errorlevel! equ 0 set "PY=python3"
)

if not defined PY (
    echo [Perce-Neige] ERROR: Python 3 not found.
    echo.
    echo   Please install Python 3.9+ from https://www.python.org/downloads/
    echo   ^(tick "Add Python to PATH" during install^) and run this launcher again.
    echo.
    pause
    exit /b 1
)

echo [Perce-Neige] Python: %PY%

if not exist "%VENVROOT%" mkdir "%VENVROOT%"

rem The venv path may contain spaces depending on the username, so always
rem quote %VENVDIR%. %PY% may be either a short command (py -3) or a raw
rem path without spaces — we call it via "cmd /c" to handle both uniformly.
if not exist "%VENVDIR%\Scripts\python.exe" (
    echo [Perce-Neige] Creating venv at %VENVDIR%
    cmd /c ""%PY%" -m venv "%VENVDIR%""
    if errorlevel 1 (
        rem Fallback : some values of %PY% are multi-word commands like
        rem "py -3" which can't be quoted — try the unquoted form.
        %PY% -m venv "%VENVDIR%"
    )
    if not exist "%VENVDIR%\Scripts\python.exe" (
        echo [Perce-Neige] Failed to create venv.
        pause
        exit /b 1
    )
)

rem Validate venv still works (broken copy from another PC)
"%VENVDIR%\Scripts\python.exe" -c "print('ok')" >nul 2>&1
if errorlevel 1 (
    echo [Perce-Neige] Rebuilding broken venv
    rmdir /s /q "%VENVDIR%" 2>nul
    cmd /c ""%PY%" -m venv "%VENVDIR%""
    if errorlevel 1 %PY% -m venv "%VENVDIR%"
    if not exist "%VENVDIR%\Scripts\python.exe" (
        echo [Perce-Neige] Failed to rebuild venv.
        pause
        exit /b 1
    )
)

set "MARKER=%VENVDIR%\.deps_installed"
set "REQ=%PROJ%requirements.txt"
fc "%MARKER%" "%REQ%" >nul 2>&1
if errorlevel 1 (
    echo [Perce-Neige] Installing dependencies
    "%VENVDIR%\Scripts\python.exe" -m pip install --upgrade pip >nul
    "%VENVDIR%\Scripts\python.exe" -m pip install -r "%REQ%"
    if errorlevel 1 (
        echo [Perce-Neige] pip install failed.
        pause
        exit /b 1
    )
    copy /y "%REQ%" "%MARKER%" >nul
)

start "" "%VENVDIR%\Scripts\pythonw.exe" "%PROJ%perce_neige_sim.py"
endlocal
