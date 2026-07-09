# Publish a PILOT APK alongside factory latest.apk on the landing Hosting site.
#
# Pilot URL (Departments / People channel APK URL):
#   https://ctp-job-cards-landing.web.app/releases/pilot.apk
#
# Factory / landing Download button stays:
#   https://ctp-job-cards-landing.web.app/releases/latest.apk
#
# Usage:
#   pwsh .\scripts\publish-landing-pilot-apk.ps1
#   pwsh .\scripts\publish-landing-pilot-apk.ps1 -BuildApk
#   pwsh .\scripts\publish-landing-pilot-apk.ps1 -SkipDeploy
#
# Critical: build-landing.js wipes landing-deploy/. This script re-adds pilot.apk
# and restores latest.apk from a local backup or the live Hosting file when possible.

param(
  [switch]$BuildApk,
  [switch]$SkipDeploy,
  # Also overwrite latest.apk with this build (NOT for Ink-only pilot).
  [switch]$AlsoLatest
)

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$AppRoot = Get-Location

$PilotUrl = "https://ctp-job-cards-landing.web.app/releases/pilot.apk"
$LatestUrl = "https://ctp-job-cards-landing.web.app/releases/latest.apk"
$ReleasesDir = Join-Path $AppRoot "landing-deploy\releases"
$PilotDest = Join-Path $ReleasesDir "pilot.apk"
$LatestDest = Join-Path $ReleasesDir "latest.apk"
$ApkSrc = Join-Path $AppRoot "build\app\outputs\flutter-apk\app-release.apk"
$BackupDir = Join-Path $AppRoot "landing-deploy-apk-backup"
$LatestBackup = Join-Path $BackupDir "latest.apk"

Write-Host "==> CTP Job Cards — publish landing pilot.apk" -ForegroundColor Cyan
Write-Host "    App root: $AppRoot"
Write-Host "    Pilot URL: $PilotUrl"

if ($BuildApk) {
  Write-Host "==> Building release APK (arm64)..." -ForegroundColor Cyan
  flutter build apk --target-platform android-arm64 --release
}

if (-not (Test-Path $ApkSrc)) {
  Write-Error "APK not found at $ApkSrc. Build first or pass -BuildApk."
}

# Preserve factory latest before wipe
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
if (Test-Path $LatestDest) {
  Copy-Item $LatestDest $LatestBackup -Force
  Write-Host "    Backed up local latest.apk" -ForegroundColor DarkGray
} elseif (-not (Test-Path $LatestBackup)) {
  Write-Host "    Trying to download live latest.apk for preserve..." -ForegroundColor DarkGray
  try {
    Invoke-WebRequest -Uri $LatestUrl -OutFile $LatestBackup -UseBasicParsing
    if ((Get-Item $LatestBackup).Length -lt 1MB) {
      Remove-Item $LatestBackup -Force -ErrorAction SilentlyContinue
    }
  } catch {
    Write-Host "    (Could not download live latest — deploy may drop factory APK until you re-publish latest.)" -ForegroundColor Yellow
  }
}

Write-Host "==> Assembling landing-deploy..." -ForegroundColor Cyan
node build-landing.js

New-Item -ItemType Directory -Force -Path $ReleasesDir | Out-Null

# Restore factory latest unless user wants this build to also be latest
if ($AlsoLatest) {
  Copy-Item $ApkSrc $LatestDest -Force
  Write-Host "    Also wrote latest.apk from this build (-AlsoLatest)" -ForegroundColor Yellow
} elseif (Test-Path $LatestBackup) {
  Copy-Item $LatestBackup $LatestDest -Force
  Write-Host ("    Restored latest.apk ({0:N1} MB)" -f ((Get-Item $LatestDest).Length / 1MB)) -ForegroundColor Green
} else {
  Write-Host "    WARNING: no latest.apk restored — landing Download may 404 until you run publish-landing-apk.ps1" -ForegroundColor Yellow
}

Copy-Item $ApkSrc $PilotDest -Force
Write-Host ("    Wrote pilot.apk ({0:N1} MB)" -f ((Get-Item $PilotDest).Length / 1MB)) -ForegroundColor Green

if ($SkipDeploy) {
  Write-Host "==> SkipDeploy — not deploying." -ForegroundColor Yellow
  Write-Host "    firebase deploy --only hosting:landing --project ctp-job-cards"
  exit 0
}

Write-Host "==> Deploying hosting:landing ..." -ForegroundColor Cyan
firebase deploy --only hosting:landing --project ctp-job-cards

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Pilot URL (Departments / People channel APK URL):"
Write-Host "  $PilotUrl"
Write-Host "Factory Shared / Default URL (keep on this unless -AlsoLatest):"
Write-Host "  $LatestUrl"
Write-Host ""
Write-Host "Admin checklist:"
Write-Host "  1. Shared download URL = latest.apk URL"
Write-Host "  2. Default channel = factory version/build (lower than pilot)"
Write-Host "  3. Departments or People: enable, select audience, version/build of THIS pilot,"
Write-Host "     Channel APK URL = pilot.apk URL, Force as needed → Save publish"
