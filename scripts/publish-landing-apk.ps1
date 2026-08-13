# Assemble landing site + upload factory APK to Cloud Storage, then deploy Hosting
# (thin landing page + redirects from legacy /releases/*.apk paths).
#
# Prerequisites: release APK already built (or pass -BuildApk).
# Requires: gcloud auth for project ctp-job-cards; Storage rules deployed
#   (releases/** public read) from monorepo /firebase.
#
# Usage (from mobile/CTPJob_Cards):
#   pwsh .\scripts\publish-landing-apk.ps1
#   pwsh .\scripts\publish-landing-apk.ps1 -BuildApk
#   pwsh .\scripts\publish-landing-apk.ps1 -SkipHosting
#
# After upload, set Admin → Shared download URL to the Storage URL printed below
# (same URL every release — object is overwritten in place).

param(
  [switch]$BuildApk,
  [switch]$SkipDeploy,
  [switch]$SkipHosting,
  [switch]$SkipUpload
)

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$AppRoot = Get-Location

. (Join-Path $PSScriptRoot "apk-release-urls.ps1")

Write-Host "==> CTP Job Cards — publish Storage latest.apk + landing" -ForegroundColor Cyan
Write-Host "    App root: $AppRoot"
Write-Host "    Canonical URL: $script:LatestApkUrl"

if ($BuildApk) {
  & (Join-Path $PSScriptRoot "invoke-flutter-release-apk.ps1")
}

$apk = Join-Path $AppRoot "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apk)) {
  Write-Error "APK not found at $apk. Build first or pass -BuildApk."
}

$apkItem = Get-Item $apk
$pubspecItem = Get-Item (Join-Path $AppRoot "pubspec.yaml")
if ($apkItem.LastWriteTimeUtc -lt $pubspecItem.LastWriteTimeUtc.AddMinutes(-1)) {
  Write-Error ("APK is older than pubspec.yaml ({0:u} < {1:u}). " +
    "Rebuild with -BuildApk — refusing to publish a stale binary as latest.apk.") -f `
    $apkItem.LastWriteTimeUtc, $pubspecItem.LastWriteTimeUtc
}
Write-Host ("    APK ready ({0:N1} MB, {1:g})" -f ($apkItem.Length / 1MB), $apkItem.LastWriteTime) -ForegroundColor Green

if (-not $SkipUpload) {
  & (Join-Path $PSScriptRoot "upload-release-apk.ps1") -Name latest -ApkPath $apk
  if ($LASTEXITCODE -ne 0) {
    Write-Error "Storage upload failed."
  }
} else {
  Write-Host "==> SkipUpload — not uploading APK to Storage" -ForegroundColor Yellow
}

Write-Host "==> Assembling landing-deploy (HTML/docs only — APK is on Storage)..." -ForegroundColor Cyan
node build-landing.js

if ($SkipDeploy -or $SkipHosting) {
  Write-Host "==> Skip hosting deploy. When ready:" -ForegroundColor Yellow
  Write-Host "    firebase deploy --only hosting:landing --project ctp-job-cards"
  exit 0
}

Write-Host "==> Deploying hosting:landing (page + legacy APK redirects)..." -ForegroundColor Cyan
firebase deploy --only hosting:landing --project ctp-job-cards

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Shared download URL / landing / in-app (set once in Admin):"
Write-Host "  $script:LatestApkUrl"
Write-Host "Legacy Hosting path still redirects (bookmarks/QR):"
Write-Host "  $script:LegacyLatestHostingUrl"
Write-Host "Admin: Shared download URL = Storage URL above; bump version/build and Save publish."
