# Optional: point this clone at tracked githooks (no build-number auto-bump).
# Build numbers are owned by /mobile-app-release and /mobile-pilot-release only.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot
git config --local core.hooksPath githooks
Write-Host "Git hooks path: $repoRoot/githooks"
Write-Host "pre-commit does NOT bump pubspec. Bump only when shipping APKs:"
Write-Host "  node scripts/bump-build-number.js   # then changelog + build"
Write-Host "  Skills: mobile-app-release | mobile-pilot-release"
