# Windows (PowerShell 5+/7, Windows 10+): builds dist\wordpressToolkitPro.zip
# Uses tar (bsdtar) because Compress-Archive writes backslash paths that break "unzip" on Linux.
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
New-Item -ItemType Directory -Force dist | Out-Null
Remove-Item -ErrorAction SilentlyContinue dist\wordpressToolkitPro.zip
tar -a -c -f dist\wordpressToolkitPro.zip wordpressToolkitPro
Write-Host "Built dist\wordpressToolkitPro.zip"
