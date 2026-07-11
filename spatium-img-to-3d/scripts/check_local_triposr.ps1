$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TriposrDir = Join-Path $Root "models\TripoSR"
$ModelDir = Join-Path $Root "models\hf\TripoSR"
$VenvPython = Join-Path $Root ".venv-triposr\Scripts\python.exe"

Write-Output "Python: $VenvPython"
Write-Output "Repo:   $TriposrDir"
Write-Output "Model:  $ModelDir"

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

if (-not (Test-Path $VenvPython)) { throw "Missing .venv-triposr. Run scripts\setup_local_triposr.ps1" }
if (-not (Test-Path $TriposrDir)) { throw "Missing TripoSR repo. Run scripts\setup_local_triposr.ps1" }
if (-not (Test-Path (Join-Path $TriposrDir "run.py"))) { throw "Missing TripoSR run.py." }
if (-not (Test-Path $ModelDir)) { throw "Missing downloaded TripoSR model. Run scripts\setup_local_triposr.ps1" }
if (-not (Get-Command cl -ErrorAction SilentlyContinue)) { throw "Missing cl.exe. Install Visual Studio C++ Build Tools." }
if (-not (Get-Command nmake -ErrorAction SilentlyContinue)) { throw "Missing nmake.exe. Install Visual Studio C++ Build Tools." }
if (-not (Get-Command nvcc -ErrorAction SilentlyContinue)) { Write-Output "nvcc not found. GPU extension builds need CUDA Toolkit; CPU mode can still work." }

& $VenvPython -c "import torch; print('torch', torch.__version__); print('cuda', torch.cuda.is_available()); print('device', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'cpu')"
Write-Output "Local TripoSR files look ready."
