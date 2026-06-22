# Enable tracked git hooks for this clone (run once after clone).
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot
git config --local core.hooksPath githooks
Write-Host "Git hooks enabled: $repoRoot/githooks (pre-commit bumps pubspec build number)"