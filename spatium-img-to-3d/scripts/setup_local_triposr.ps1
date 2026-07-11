param(
    [switch]$Cpu,
    [switch]$SkipBuildToolsCheck
)

$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TriposrDir = Join-Path $Root "models\TripoSR"
$ModelDir = Join-Path $Root "models\hf\TripoSR"
$VenvPython = Join-Path $Root ".venv-triposr\Scripts\python.exe"

Set-Location $Root
$env:UV_CACHE_DIR = ".uv-cache"

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE"
    }
}

function Import-VsBuildTools {
    if ((Get-Command cl -ErrorAction SilentlyContinue) -and (Get-Command nmake -ErrorAction SilentlyContinue)) {
        return
    }

    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"),
        (Join-Path $env:ProgramFiles "Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            $envLines = cmd /s /c "`"$candidate`" >nul && set"
            foreach ($line in $envLines) {
                $parts = $line -split "=", 2
                if ($parts.Length -eq 2) {
                    Set-Item -Path "Env:$($parts[0])" -Value $parts[1]
                }
            }
            return
        }
    }
}

function Import-CudaToolkit {
    if (Get-Command nvcc -ErrorAction SilentlyContinue) {
        return
    }

    $candidates = @(
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.1",
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8",
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6"
    )

    foreach ($candidate in $candidates) {
        $nvcc = Join-Path $candidate "bin\nvcc.exe"
        if (Test-Path $nvcc) {
            $env:CUDA_PATH = $candidate
            $env:CUDA_HOME = $candidate
            $env:CUDA_PATH_V12_1 = $candidate
            $env:CUDA_PATH_V12_8 = $candidate
            $env:CUDAToolkit_ROOT = $candidate
            $env:CudaToolkitDir = "$candidate\"
            $env:CMAKE_CUDA_COMPILER = $nvcc
            $env:Path = "$(Join-Path $candidate 'bin');$(Join-Path $candidate 'libnvvp');$env:Path"
            return
        }
    }
}

Import-VsBuildTools
Import-CudaToolkit
$hasNvcc = [bool](Get-Command nvcc -ErrorAction SilentlyContinue)
if (-not $Cpu -and -not $hasNvcc) {
    Write-Output "CUDA Toolkit nvcc was not found. Installing CPU PyTorch for a working local setup."
    Write-Output "Install CUDA Toolkit and rerun without -Cpu if you want GPU extension builds."
    $Cpu = $true
}

if (-not $SkipBuildToolsCheck) {
    $cl = Get-Command cl -ErrorAction SilentlyContinue
    $nmake = Get-Command nmake -ErrorAction SilentlyContinue
    if (-not $cl -or -not $nmake) {
        throw @"
Missing Microsoft C++ Build Tools.

TripoSR depends on torchmcubes, which must compile native C++ code on Windows.
Install "Visual Studio 2022 Build Tools" with the C++ build tools workload, then run this script again.

After installing, open "Developer PowerShell for VS 2022" or restart your terminal.
Use -SkipBuildToolsCheck only if cl.exe and nmake.exe are available through another setup.
"@
    }
}

New-Item -ItemType Directory -Force "models" | Out-Null
New-Item -ItemType Directory -Force "models\hf" | Out-Null

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git is required to install TripoSR."
}

if (-not (Test-Path $TriposrDir)) {
    Invoke-Native git clone https://github.com/VAST-AI-Research/TripoSR.git $TriposrDir
}

if (-not (Test-Path $VenvPython)) {
    Invoke-Native uv venv .venv-triposr --python 3.11
}

Invoke-Native uv pip install --python $VenvPython --upgrade pip setuptools wheel

if ($Cpu) {
    Invoke-Native uv pip install --python $VenvPython torch==2.5.1 torchvision==0.20.1 --index-url https://download.pytorch.org/whl/cpu
} else {
    Invoke-Native uv pip install --python $VenvPython torch==2.5.1+cu124 torchvision==0.20.1+cu124 --index-url https://download.pytorch.org/whl/cu124
}

$torchCmakePath = & $VenvPython -c "import torch; print(torch.utils.cmake_prefix_path)"
if ($LASTEXITCODE -ne 0) {
    throw "Could not read PyTorch CMake path."
}
$env:CMAKE_PREFIX_PATH = $torchCmakePath
if ($hasNvcc) {
    $env:SKBUILD_CMAKE_ARGS = "-DCUDAToolkit_ROOT=$env:CUDA_PATH;-DCMAKE_CUDA_COMPILER=$env:CMAKE_CUDA_COMPILER"
}

Invoke-Native uv pip install --python $VenvPython scikit-build-core cmake ninja pybind11
Invoke-Native uv pip install --python $VenvPython --no-build-isolation -r (Join-Path $TriposrDir "requirements.txt")

& $VenvPython -c "from huggingface_hub import snapshot_download; snapshot_download(repo_id='stabilityai/TripoSR', local_dir=r'$ModelDir')"
if ($LASTEXITCODE -ne 0) {
    throw "Model download failed with exit code $LASTEXITCODE"
}

Write-Output "Local TripoSR setup complete."
Write-Output "Run server: .\run_server.bat"
Write-Output "Then choose 'Local TripoSR' in the UI."
