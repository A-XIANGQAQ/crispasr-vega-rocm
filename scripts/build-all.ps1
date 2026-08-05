# ============================================================
# CrispASR Vega ROCm - One-Click Build Script
# Compiles CrispASR with HIP acceleration + Shim DLL
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\build-all.ps1 [-RocmPath "C:\path\to\therock"]
#
# This script:
#   1. Mirrors crispasr/ source to a space-free path (hipcc requirement)
#   2. Compiles CrispASR with TheRock hipcc (gfx900, code object v4)
#   3. Compiles the ABI bridge Shim DLL
#   4. Copies output binaries to bin-hip/
# ============================================================

param(
    [string]$RocmPath = "",
    [string]$MirrorDir = "C:\cabuild\crispasr"
)

$ErrorActionPreference = "Stop"
$REPO_ROOT = $PSScriptRoot | Split-Path -Parent
$CRISPASR_SRC = "$REPO_ROOT\crispasr"

Write-Host "============================================================"
Write-Host " CrispASR Vega ROCm - One-Click Build"
Write-Host "============================================================"
Write-Host ""

# ----------------------------------------------------------
# Step 0: Verify prerequisites
# ----------------------------------------------------------
Write-Host "[0/5] Checking prerequisites..."

if (-not (Test-Path "$CRISPASR_SRC\CMakeLists.txt")) {
    Write-Host "[ERROR] CrispASR source not found at: $CRISPASR_SRC"
    Write-Host "  Make sure you cloned with: git clone --recursive"
    exit 1
}
Write-Host "  [OK] CrispASR source found"

# Auto-detect TheRock ROCm SDK
if (-not $RocmPath) {
    $envRocm = $env:ROCM_PATH
    if ($envRocm -and (Test-Path "$envRocm\bin\hipcc.exe")) {
        $RocmPath = $envRocm
    } else {
        $defaultRocm = "$REPO_ROOT\therock\venv\lib\site-packages\_rocm_sdk_devel"
        if (Test-Path "$defaultRocm\bin\hipcc.exe") {
            $RocmPath = $defaultRocm
        } else {
            Write-Host "[ERROR] TheRock ROCm SDK not found!"
            Write-Host "  Install with:"
            Write-Host "    python -m venv therock\venv"
            Write-Host "    therock\venv\Scripts\Activate.ps1"
            Write-Host "    pip install therock-tools"
            Write-Host "    therock install --device-gfx900"
            Write-Host "  Or specify with -RocmPath parameter"
            exit 1
        }
    }
}
Write-Host "  [OK] TheRock ROCm SDK: $RocmPath"

# Check VS 2022
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    Write-Host "[ERROR] Visual Studio 2022 not found"
    exit 1
}
$VS_PATH = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
Write-Host "  [OK] Visual Studio: $VS_PATH"

# ----------------------------------------------------------
# Step 1: Mirror source to space-free path
# ----------------------------------------------------------
Write-Host ""
Write-Host "[1/5] Mirroring source to space-free path (hipcc requirement)..."
Write-Host "  Source:  $CRISPASR_SRC"
Write-Host "  Mirror:  $MirrorDir"

# Clean old mirror build dirs before robocopy (save time)
$buildDirs = @('build-hip-therock', 'bin-hip', 'build-opencl', 'build-vulkan', 'build-hip')
foreach ($bd in $buildDirs) {
    $bdPath = Join-Path $MirrorDir $bd
    if (Test-Path $bdPath) { Remove-Item $bdPath -Recurse -Force -ErrorAction SilentlyContinue }
}

& robocopy $CRISPASR_SRC $MirrorDir /MIR /XD .git therock node_modules /XF *.gguf *.wav *.dll *.exe /NFL /NDL /NJH /NJS /NP
if ($LASTEXITCODE -ge 8) {
    Write-Host "[ERROR] robocopy failed with exit code $LASTEXITCODE"
    exit 1
}
Write-Host "  [OK] Source mirrored"

# ----------------------------------------------------------
# Step 2: Build CrispASR with TheRock clang 23 (hipcc-wrap)
# ----------------------------------------------------------
Write-Host ""
Write-Host "[2/5] Building CrispASR with TheRock hipcc..."

# Set Vega environment variables
$env:HSA_OVERRIDE_GFX_VERSION = "9.0.0"
$env:HSA_ENABLE_SDMA = "0"
$env:HIP_VISIBLE_DEVICES = "0"
$env:ROCM_PATH = $RocmPath
$env:HIP_PATH = "$RocmPath\bin"
$env:PATH = "$RocmPath\bin;" + $env:PATH

# Load MSVC (required for linking against MSVC STL + clang host toolchain)
$devShellModule = Join-Path $VS_PATH "Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
Import-Module $devShellModule
Enter-VsDevShell -VsInstallPath $VS_PATH -SkipAutomaticLocation -DevCmdArguments "-arch=x64 -host_arch=x64"

# Check Ninja
$ninjaExe = Get-Command ninja -ErrorAction SilentlyContinue
if ($ninjaExe) {
    $generator = "Ninja"
    Write-Host "  Using Ninja: $($ninjaExe.Source)"
} else {
    # Try known Ninja path
    $ninjaPath = "C:\Users\A-xiang\AppData\Local\Microsoft\WinGet\Packages\Ninja-build.Ninja_Microsoft.Winget.Source_8wekyb3d8bbwe\ninja.exe"
    if (Test-Path $ninjaPath) {
        $env:PATH = "$(Split-Path $ninjaPath);" + $env:PATH
        $generator = "Ninja"
        Write-Host "  Using Ninja (WinGet): $ninjaPath"
    } else {
        $generator = "NMake Makefiles"
        Write-Host "  Using NMake (slower, no parallel)"
    }
}

# --- 2nd-build fix: do NOT call hipcc.exe directly -------------------------
# hipcc.pl needs a working Perl and ROCm 5.7's clang 17 is incompatible with
# MSVC STL 14.51+ (constexpr errors in xutility/xlocnum). All compilation must
# go through TheRock clang 23 directly via a generated wrapper. Clang only
# accepts space-free paths, so the wrapper lives in the (space-free) mirror
# dir and references the ROCm SDK by its 8.3 short path.
# ---------------------------------------------------------------------------
Write-Host "  Generating hipcc-wrap.bat (TheRock clang 23, short path)..."
$clangExe = "$RocmPath\lib\llvm\bin\clang.exe"
if (-not (Test-Path $clangExe)) {
    Write-Host "[ERROR] TheRock clang not found at: $clangExe"
    Write-Host "  Expected layout: <sdk>\lib\llvm\bin\clang.exe (pip therock-tools layout)"
    exit 1
}
$fso = New-Object -ComObject Scripting.FileSystemObject
$rocmShort = $fso.GetFolder($RocmPath).ShortPath

$wrapBat = "$MirrorDir\hipcc-wrap.bat"
@"
@echo off
rem Generated by build-all.ps1 — direct TheRock clang 23 compilation.
rem Bypasses hipcc.pl (Perl) and ROCm 5.7 clang 17 (MSVC STL 14.51+ incompat).
rem -mcode-object-version=4 is injected via CMAKE_CXX_FLAGS (ROCm 5.7 runtime).
set "LC_ALL=C"
set "LANG=C"
set "ROCM_SHORT=$rocmShort"
"%ROCM_SHORT%\lib\llvm\bin\clang.exe" --rocm-path=%ROCM_SHORT% --rocm-device-lib-path=%ROCM_SHORT%\lib\llvm\amdgcn\bitcode -D__AMDGCN_WAVEFRONT_SIZE=64 %*
exit /b %errorlevel%
"@ | Set-Content $wrapBat -Encoding ASCII
Write-Host "  [OK] $wrapBat"

# --- 2nd-build fix: clang builtins for the SHARED lib (ggml-hip.dll) --------
# The CLI target auto-detects clang_rt.builtins-x86_64.lib in its CMakeLists,
# but ggml-hip.dll is a shared library and does NOT — without this flag,
# lld-link fails with "undefined symbol: __truncsfhf2" (and __cpu_model).
# ---------------------------------------------------------------------------
$builtinsLong = (& $clangExe --print-file-name=clang_rt.builtins-x86_64.lib 2>$null | Select-Object -Last 1)
if (-not $builtinsLong -or -not (Test-Path $builtinsLong)) {
    Write-Host "[ERROR] Could not locate clang_rt.builtins-x86_64.lib via clang --print-file-name"
    exit 1
}
$builtinsShort = $fso.GetFile($builtinsLong).ShortPath
Write-Host "  [OK] clang builtins: $builtinsShort"

$BUILD_DIR = "$MirrorDir\build-hip-therock"
$OUT_DIR = "$MirrorDir\bin-hip"

Push-Location $MirrorDir
try {
    # Configure CMake
    Write-Host "  Configuring CMake..."
    cmake -G $generator -B $BUILD_DIR `
        -DCMAKE_BUILD_TYPE=Release `
        -DCMAKE_C_COMPILER=$wrapBat `
        -DCMAKE_CXX_COMPILER=$wrapBat `
        "-DCMAKE_SHARED_LINKER_FLAGS=$builtinsShort" `
        -DCMAKE_PREFIX_PATH="$RocmPath\lib\cmake;$RocmPath\share\rocm\cmake" `
        -DROCM_PATH="$RocmPath" `
        -DGGML_HIP=ON `
        -DGGML_HIP_GRAPHS=OFF `
        -DGGML_HIP_NO_VMM=ON `
        -DGGML_HIP_ROCWMMA_FATTN=OFF `
        -DGGML_HIP_MMQ_MFMA=OFF `
        -DGGML_CUDA=OFF `
        -DGGML_VULKAN=OFF `
        -DGGML_OPENCL=OFF `
        -DGGML_METAL=OFF `
        -DAMDGPU_TARGETS="gfx900" `
        -DGPU_TARGETS="gfx900" `
        -DCMAKE_HIP_ARCHITECTURES="gfx900" `
        -DGGML_LLAMAFILE_DEFAULT=ON `
        -DCRISPASR_BUILD_EXAMPLES=ON `
        -DCRISPASR_BUILD_TESTS=OFF `
        -DCMAKE_RUNTIME_OUTPUT_DIRECTORY_RELEASE=$OUT_DIR `
        -DCMAKE_RUNTIME_OUTPUT_DIRECTORY=$OUT_DIR

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] CMake configuration failed!"
        exit 1
    }

    # Add code object version 4 to CMake cache (critical for ROCm 5.7 compatibility)
    $cacheFile = "$BUILD_DIR\CMakeCache.txt"
    if (Test-Path $cacheFile) {
        $cache = Get-Content $cacheFile -Raw
        if ($cache -notmatch 'mcode-object-version') {
            # Append to CMAKE_CXX_FLAGS and CMAKE_C_FLAGS
            $cache = $cache -replace '(CMAKE_CXX_FLAGS:STRING=[^\r\n]*)', '$1 -mcode-object-version=4'
            $cache = $cache -replace '(CMAKE_C_FLAGS:STRING=[^\r\n]*)', '$1 -mcode-object-version=4'
            Set-Content $cacheFile -Value $cache -Encoding UTF8
            Write-Host "  [OK] Added -mcode-object-version=4 to CMake cache"
        }
    }

    # Build (use -j 2 to avoid clang frontend crashes)
    Write-Host "  Building (this may take 10-20 minutes)..."
    Write-Host "  Using -j 2 parallelism (memory safety for clang)"

    # 2nd-build fix: a stale .ninja_lock from an interrupted build makes ninja
    # fail with "WriteFile(.ninja_lock): Permission denied"
    if (Test-Path "$BUILD_DIR\.ninja_lock") {
        Remove-Item "$BUILD_DIR\.ninja_lock" -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] Removed stale .ninja_lock"
    }

    if ($generator -eq "Ninja") {
        cmake --build $BUILD_DIR --config Release -j 2 --target crispasr-cli
    } else {
        cmake --build $BUILD_DIR --config Release --target crispasr-cli
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Build failed!"
        exit 1
    }
    Write-Host "  [OK] CrispASR compiled successfully"
} finally {
    Pop-Location
}

# ----------------------------------------------------------
# Step 3: Compile Shim DLL
# ----------------------------------------------------------
Write-Host ""
Write-Host "[3/5] Compiling ABI bridge Shim DLL..."

$SHIM_SRC = "$REPO_ROOT\hip-shim"
Push-Location $SHIM_SRC
try {
    cl /O2 /GS- /c hip_shim.c
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Shim DLL compilation failed (cl step)"
        exit 1
    }
    link /DLL /OUT:amdhip64_7.dll hip_shim.obj /DEF:hip_shim.def /NODEFAULTLIB kernel32.lib
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Shim DLL linking failed (link step)"
        exit 1
    }
    Write-Host "  [OK] Shim DLL compiled: amdhip64_7.dll"
} finally {
    Pop-Location
}

# ----------------------------------------------------------
# Step 4: Copy binaries to repo bin-hip/
# ----------------------------------------------------------
Write-Host ""
Write-Host "[4/5] Copying binaries..."

$REPO_BIN = "$REPO_ROOT\bin-hip"
New-Item -ItemType Directory -Force -Path $REPO_BIN | Out-Null

# Copy crispasr.exe and ggml-hip.dll from build output
$builtExe = "$OUT_DIR\crispasr.exe"
$builtDll = "$OUT_DIR\ggml-hip.dll"

if (Test-Path $builtExe) {
    Copy-Item $builtExe $REPO_BIN -Force
    Write-Host "  [OK] crispasr.exe"
} else {
    Write-Host "  [WARN] crispasr.exe not found at $builtExe"
}

if (Test-Path $builtDll) {
    Copy-Item $builtDll $REPO_BIN -Force
    Write-Host "  [OK] ggml-hip.dll"
} else {
    Write-Host "  [WARN] ggml-hip.dll not found at $builtDll"
}

# Copy Shim DLL
$shimDll = "$SHIM_SRC\amdhip64_7.dll"
if (Test-Path $shimDll) {
    Copy-Item $shimDll $REPO_BIN -Force
    Write-Host "  [OK] amdhip64_7.dll (Shim)"
}

# Copy run script
Copy-Item "$REPO_ROOT\scripts\run_crispasr_hip.bat" $REPO_BIN -Force
Write-Host "  [OK] run_crispasr_hip.bat"

# ----------------------------------------------------------
# Step 5: Copy ROCm runtime DLLs
# ----------------------------------------------------------
Write-Host ""
Write-Host "[5/5] Copying ROCm runtime DLLs..."

$ROCM57_BIN = "C:\Program Files\AMD\ROCm\5.7\bin"
$THEROCK_BIN = "$RocmPath\bin"

# ROCm 5.7 DLLs (runtime)
$rocm57Dlls = @(
    'amdhip64.dll',
    'amd_comgr.dll',
    'rocblas.dll',
    'origami.dll'
)

foreach ($dll in $rocm57Dlls) {
    $src = Join-Path $ROCM57_BIN $dll
    if (Test-Path $src) {
        Copy-Item $src $REPO_BIN -Force
        Write-Host "  [OK] $dll (ROCm 5.7)"
    } else {
        Write-Host "  [WARN] $dll not found in ROCm 5.7"
    }
}

# rocblas library folder
# NOTE (2nd build): GEMM on gfx900 is broken in every rocBLAS variant tried
# (Sgemm/GemmEx all return CUBLAS_STATUS_INTERNAL_ERROR); ggml-cuda.cu now
# ships custom vega_* GEMM kernels that short-circuit cc == GGML_CUDA_CC_VEGA.
# rocblas.dll is still copied because hipblas initialization requires it to
# exist, but the Tensile library is no longer performance-critical.
$rocblasLib = "$ROCM57_BIN\rocblas\library"
if (Test-Path $rocblasLib) {
    $dstLib = "$REPO_BIN\rocblas\library"
    New-Item -ItemType Directory -Force -Path $dstLib | Out-Null
    Copy-Item "$rocblasLib\*" $dstLib -Force -Recurse
    Write-Host "  [OK] rocblas\library\ (gfx900 kernels)"
}

# TheRock DLLs
$therockDlls = @(
    'hipblas.dll',
    'rocm_kpack.dll',
    'libomp140.x86_64.dll'
)

foreach ($dll in $therockDlls) {
    $src = Join-Path $THEROCK_BIN $dll
    if (Test-Path $src) {
        Copy-Item $src $REPO_BIN -Force
        Write-Host "  [OK] $dll (TheRock)"
    } else {
        Write-Host "  [WARN] $dll not found in TheRock"
    }
}

# clang builtins lib (needed at link time, copy for reference)
$builtinsLib = Get-ChildItem "$RocmPath\lib\clang\*\lib\windows\clang_rt.builtins-x86_64.lib" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($builtinsLib) {
    Copy-Item $builtinsLib.FullName $REPO_BIN -Force
    Write-Host "  [OK] clang_rt.builtins-x86_64.lib"
}

# ----------------------------------------------------------
# Done
# ----------------------------------------------------------
Write-Host ""
Write-Host "============================================================"
Write-Host " BUILD COMPLETE!"
Write-Host "============================================================"
Write-Host ""
Write-Host "Binaries in: $REPO_BIN"
Write-Host ""
Write-Host "Run with:"
Write-Host "  cd bin-hip"
Write-Host "  set HSA_OVERRIDE_GFX_VERSION=9.0.0"
Write-Host "  set HSA_ENABLE_SDMA=0"
Write-Host "  crispasr.exe -m auto -f audio.wav    (auto-download model)"
Write-Host "  crispasr.exe --backend kokoro -m auto --tts ""Hello"" --tts-output out.wav"
Write-Host ""
Write-Host "Or use: scripts\run_crispasr_hip.bat"
Write-Host ""
