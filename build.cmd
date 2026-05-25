@echo off
setlocal enabledelayedexpansion

set "OPT=%~1"
if "%OPT%"=="clean" goto :clean
if "%OPT%"=="debug" (
    set "ZIG_OPT=Debug"
) else (
    set "ZIG_OPT=ReleaseFast"
)

echo === Ghostel Windows Build [%ZIG_OPT%] ===
echo.

:: Check Zig
where zig >nul 2>&1
if errorlevel 1 (
    echo ERROR: zig not found in PATH. Install Zig 0.15.2+ from https://ziglang.org/download/
    exit /b 1
)

:: Zig 0.15.2 panics (Run.zig:662 assertion) when the global cache
:: lives on a different drive than the project.  Pin it to the repo
:: directory so all paths stay on the same drive letter.
if "%ZIG_GLOBAL_CACHE_DIR%"=="" (
    set "ZIG_GLOBAL_CACHE_DIR=%~dp0.zig-global-cache"
)

:: Detect Emacs include dir if not set
if "%EMACS_INCLUDE_DIR%"=="" (
    for /f "delims=" %%d in ('dir /s /b "C:\Program Files\Emacs\emacs-module.h" 2^>nul') do (
        if "!EMACS_INCLUDE_DIR!"=="" (
            for %%p in ("%%~dpd.") do set "EMACS_INCLUDE_DIR=%%~fp"
        )
    )
    if "!EMACS_INCLUDE_DIR!"=="" (
        echo ERROR: EMACS_INCLUDE_DIR not set and emacs-module.h not found under C:\Program Files\Emacs
        echo   Set it to your Emacs include directory, e.g.:
        echo   set EMACS_INCLUDE_DIR=C:\Program Files\Emacs\emacs-30.2\include
        exit /b 1
    )
    echo       Detected Emacs include: !EMACS_INCLUDE_DIR!
)

:: Build ghostel-module.dll (GNU ABI avoids MSVC libcpmt linking issues)
echo Building ghostel-module.dll...
zig build -Doptimize=%ZIG_OPT% -Dtarget=native-native-gnu
if errorlevel 1 (
    echo ERROR: Failed to build ghostel module.
    exit /b 1
)

echo.
echo === Build complete! ===
echo ghostel-module.dll is ready.
exit /b 0

:clean
echo Cleaning build artifacts...
if exist zig-out rmdir /s /q zig-out
if exist .zig-cache rmdir /s /q .zig-cache
if exist .zig-global-cache rmdir /s /q .zig-global-cache
if exist ghostel-module.dll del ghostel-module.dll
if exist ghostel-module.version del ghostel-module.version
echo Done.
exit /b 0
