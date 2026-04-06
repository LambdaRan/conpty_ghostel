@echo off
setlocal enabledelayedexpansion

echo === Ghostel Windows Build ===
echo.

:: Check Zig
where zig >nul 2>&1
if errorlevel 1 (
    echo ERROR: zig not found in PATH. Install Zig 0.15.2+ from https://ziglang.org/download/
    exit /b 1
)

:: Check submodule
if not exist vendor\ghostty\build.zig (
    echo Initializing ghostty submodule...
    git submodule update --init vendor\ghostty
    if errorlevel 1 (
        echo ERROR: Failed to initialize ghostty submodule.
        exit /b 1
    )
)

:: Use a global cache on the same drive to avoid cross-drive absolute path
:: issues with Zig 0.15.2 (Run.zig:662 assertion).
if "%ZIG_GLOBAL_CACHE_DIR%"=="" (
    set "ZIG_GLOBAL_CACHE_DIR=%~dp0.zig-global-cache"
)

:: Build libghostty-vt with GNU ABI (avoids MSVC libcpmt linking issues)
echo Building libghostty-vt...
pushd vendor\ghostty
zig build -Demit-lib-vt=true -Doptimize=ReleaseFast -Dtarget=native-native-gnu
if errorlevel 1 (
    echo ERROR: Failed to build libghostty-vt.
    popd
    exit /b 1
)
popd

:: Copy dependency libraries from zig-cache
echo Copying dependency libraries...
set "SIMDUTF="
set "HIGHWAY="
for /f "delims=" %%f in ('dir /s /b vendor\ghostty\.zig-cache\simdutf.lib 2^>nul') do (
    if "!SIMDUTF!"=="" set "SIMDUTF=%%f"
)
for /f "delims=" %%f in ('dir /s /b vendor\ghostty\.zig-cache\highway.lib 2^>nul') do (
    if "!HIGHWAY!"=="" set "HIGHWAY=%%f"
)
if "!SIMDUTF!"=="" (
    echo ERROR: Could not find simdutf.lib in zig-cache
    exit /b 1
)
if "!HIGHWAY!"=="" (
    echo ERROR: Could not find highway.lib in zig-cache
    exit /b 1
)
copy "!SIMDUTF!" vendor\ghostty\zig-out\lib\simdutf.lib >nul
if errorlevel 1 (
    echo ERROR: Failed to copy simdutf.lib from "!SIMDUTF!"
    exit /b 1
)
copy "!HIGHWAY!" vendor\ghostty\zig-out\lib\highway.lib >nul
if errorlevel 1 (
    echo ERROR: Failed to copy highway.lib from "!HIGHWAY!"
    exit /b 1
)

:: Detect Emacs include dir if not set
if "%EMACS_INCLUDE_DIR%"=="" (
    :: Try to find emacs-module.h under Program Files\Emacs
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
    echo Detected Emacs include dir: !EMACS_INCLUDE_DIR!
)

:: Build ghostel module with GNU ABI
echo Building ghostel-module.dll...
zig build -Doptimize=ReleaseFast -Dtarget=native-native-gnu
if errorlevel 1 (
    echo ERROR: Failed to build ghostel module.
    exit /b 1
)

echo.
echo === Build complete! ===
echo ghostel-module.dll is ready.
echo.
echo To use in Emacs:
echo   (add-to-list 'load-path "%cd:\=/%")
echo   (require 'ghostel)
