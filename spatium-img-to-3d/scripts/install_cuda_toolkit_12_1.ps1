$ErrorActionPreference = "Stop"

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget is required for this helper. Install NVIDIA CUDA Toolkit 12.1 manually if winget is unavailable."
}

winget install Nvidia.CUDA `
    --version 12.1 `
    --accept-package-agreements `
    --accept-source-agreements

Write-Output "CUDA Toolkit 12.1 installer finished. Restart your terminal before running setup_local_triposr.ps1 again."
