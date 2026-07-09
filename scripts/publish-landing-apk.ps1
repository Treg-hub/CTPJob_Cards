# Assemble landing site + official APK and deploy to Firebase Hosting (landing).
# Prerequisites: release APK already built (or pass -BuildApk).
#
# Usage (from repo anywhere):
#   pwsh mobile/CTPJob_Cards/scripts/publish-landing-apk.ps1
#   pwsh mobile/CTPJob_Cards/scripts/publish-landing-apk.ps1 -BuildApk
#
# After deploy, set Admin → Shared download URL to:
#   https://ctp-job-cards-landing.web.app/releases/latest.apk

param(
  [switch]$BuildApk,
  [switch]$SkipDeploy
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path (Join-Path $PSScriptRoot "..\pubspec.yaml"))) {
  $Root = Split-Path -Parent $PSScriptRoot
}
Set-Location (Join-Path $PSScriptRoot "..")
$AppRoot = Get-Location

Write-Host "==> CTP Job Cards — publish landing + latest.apk" -ForegroundColor Cyan
Write-Host "    App root: $AppRoot"

if ($BuildApk) {
  Write-Host "==> Building release APK (arm64)..." -ForegroundColor Cyan
  flutter build apk --target-platform android-arm64 --release
}

$apk = Join-Path $AppRoot "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apk)) {
  Write-Error "APK not found at $apk. Build first or pass -BuildApk."
}

Write-Host "==> Assembling landing-deploy (includes releases/latest.apk)..." -ForegroundColor Cyan
node build-landing.js

$dest = Join-Path $AppRoot "landing-deploy\releases\latest.apk"
if (-not (Test-Path $dest)) {
  Write-Error "latest.apk was not copied into landing-deploy. Check build-landing.js output."
}

$len = (Get-Item $dest).Length
Write-Host ("    latest.apk size: {0:N1} MB" -f ($len / 1MB)) -ForegroundColor Green

if ($SkipDeploy) {
  Write-Host "==> SkipDeploy set — not deploying. Run:" -ForegroundColor Yellow
  Write-Host "    firebase deploy --only hosting:landing --project ctp-job-cards"
  exit 0
}

Write-Host "==> Deploying hosting:landing ..." -ForegroundColor Cyan
firebase deploy --only hosting:landing --project ctp-job-cards

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Download / in-app URL:"
Write-Host "  https://ctp-job-cards-landing.web.app/releases/latest.apk"
Write-Host "Admin: set Shared download URL to that link; bump version/build and Save publish."
