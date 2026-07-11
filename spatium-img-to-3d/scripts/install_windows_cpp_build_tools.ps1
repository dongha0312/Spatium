$ErrorActionPreference = "Stop"

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget is required for this helper. Install Visual Studio 2022 Build Tools manually if winget is unavailable."
}

winget install Microsoft.VisualStudio.2022.BuildTools `
    --accept-package-agreements `
    --accept-source-agreements `
    --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"

Write-Output "Visual Studio Build Tools installer finished. Restart your terminal before running setup_local_triposr.ps1 again."
