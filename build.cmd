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

:: Ensure vendor/ghostty exists
if not exist vendor\ghostty\build.zig (
    echo ERROR: vendor\ghostty not found.
    echo   Run: git submodule update --init vendor\ghostty
    exit /b 1
)

:: Use a global cache on the same drive to avoid cross-drive absolute path
:: issues with Zig 0.15.2 (Run.zig:662 assertion).
if "%ZIG_GLOBAL_CACHE_DIR%"=="" (
    set "ZIG_GLOBAL_CACHE_DIR=%~dp0.zig-global-cache"
)

:: Step 1: Build libghostty-vt (GNU ABI avoids MSVC libcpmt linking issues)
echo [1/3] Building libghostty-vt...
pushd vendor\ghostty
zig build -Demit-lib-vt=true -Doptimize=%ZIG_OPT% -Dtarget=native-native-gnu
if errorlevel 1 (
    echo ERROR: Failed to build libghostty-vt.
    popd
    exit /b 1
)
popd
echo       OK

:: Step 2: Copy C++ dependency libraries from zig-cache to zig-out/lib
echo [2/3] Copying dependency libraries...
for %%L in (simdutf highway utfcpp) do (
    set "FOUND="
    for /f "delims=" %%f in ('dir /s /b vendor\ghostty\.zig-cache\%%L.lib 2^>nul') do (
        if "!FOUND!"=="" set "FOUND=%%f"
    )
    if "!FOUND!"=="" (
        echo ERROR: Could not find %%L.lib in vendor\ghostty\.zig-cache
        exit /b 1
    )
    copy "!FOUND!" vendor\ghostty\zig-out\lib\%%L.lib >nul
    if errorlevel 1 (
        echo ERROR: Failed to copy %%L.lib
        exit /b 1
    )
)
echo       OK

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

:: Step 3: Build ghostel-module.dll (GNU ABI)
echo [3/3] Building ghostel-module.dll...
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
if exist ghostel-module.dll del ghostel-module.dll
if exist vendor\ghostty\zig-out rmdir /s /q vendor\ghostty\zig-out
if exist vendor\ghostty\.zig-cache rmdir /s /q vendor\ghostty\.zig-cache
echo Done.
exit /b 0
