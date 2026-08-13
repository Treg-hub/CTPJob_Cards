# Publish a PILOT APK to Cloud Storage (stable pilot.apk object).
# Factory latest.apk on Storage is left alone unless -AlsoLatest.
#
# Pilot URL (Departments / People channel APK URL):
#   (see apk-release-urls.ps1 — Storage, not Hosting)
#
# Usage:
#   pwsh .\scripts\publish-landing-pilot-apk.ps1
#   pwsh .\scripts\publish-landing-pilot-apk.ps1 -BuildApk
#   pwsh .\scripts\publish-landing-pilot-apk.ps1 -AlsoLatest
#   pwsh .\scripts\publish-landing-pilot-apk.ps1 -SkipDeploy

param(
  [switch]$BuildApk,
  [switch]$SkipDeploy,
  [switch]$SkipHosting,
  # Also overwrite Storage latest.apk with this build (NOT for Ink-only pilot).
  [switch]$AlsoLatest
)

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$AppRoot = Get-Location

. (Join-Path $PSScriptRoot "apk-release-urls.ps1")

$ApkSrc = Join-Path $AppRoot "build\app\outputs\flutter-apk\app-release.apk"

Write-Host "==> CTP Job Cards — publish Storage pilot.apk" -ForegroundColor Cyan
Write-Host "    App root: $AppRoot"
Write-Host "    Pilot URL: $script:PilotApkUrl"

if ($BuildApk) {
  & (Join-Path $PSScriptRoot "invoke-flutter-release-apk.ps1")
}

if (-not (Test-Path $ApkSrc)) {
  Write-Error "APK not found at $ApkSrc. Build first or pass -BuildApk."
}

$apkItem = Get-Item $ApkSrc
$pubspecItem = Get-Item (Join-Path $AppRoot "pubspec.yaml")
if ($apkItem.LastWriteTimeUtc -lt $pubspecItem.LastWriteTimeUtc.AddMinutes(-1)) {
  Write-Error ("APK is older than pubspec.yaml ({0:u} < {1:u}). " +
    "Rebuild with -BuildApk — refusing to publish a stale binary as pilot.apk.") -f `
    $apkItem.LastWriteTimeUtc, $pubspecItem.LastWriteTimeUtc
}
Write-Host ("    APK ready ({0:N1} MB, {1:g})" -f ($apkItem.Length / 1MB), $apkItem.LastWriteTime) -ForegroundColor Green

& (Join-Path $PSScriptRoot "upload-release-apk.ps1") -Name pilot -ApkPath $ApkSrc
if ($LASTEXITCODE -ne 0) {
  Write-Error "pilot.apk Storage upload failed."
}

if ($AlsoLatest) {
  Write-Host "==> Also uploading as latest.apk (-AlsoLatest)" -ForegroundColor Yellow
  & (Join-Path $PSScriptRoot "upload-release-apk.ps1") -Name latest -ApkPath $ApkSrc
  if ($LASTEXITCODE -ne 0) {
    Write-Error "latest.apk Storage upload failed."
  }
}

# Landing page rarely changes on pilot-only ships; still refresh redirects/docs if needed.
Write-Host "==> Assembling landing-deploy (HTML/docs only)..." -ForegroundColor Cyan
node build-landing.js

if ($SkipDeploy -or $SkipHosting) {
  Write-Host "==> Skip hosting deploy." -ForegroundColor Yellow
  Write-Host "    firebase deploy --only hosting:landing --project ctp-job-cards"
  exit 0
}

Write-Host "==> Deploying hosting:landing ..." -ForegroundColor Cyan
firebase deploy --only hosting:landing --project ctp-job-cards

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Pilot URL (Departments / People channel APK URL):"
Write-Host "  $script:PilotApkUrl"
Write-Host "Factory Shared / Default URL:"
Write-Host "  $script:LatestApkUrl"
Write-Host ""
Write-Host "Admin checklist:"
Write-Host "  1. Shared download URL = latest Storage URL (set once)"
Write-Host "  2. Default channel = factory version/build (lower than pilot)"
Write-Host "  3. Departments or People: enable, select audience, version/build of THIS pilot,"
Write-Host "     Channel APK URL = pilot Storage URL, Force as needed → Save publish"
