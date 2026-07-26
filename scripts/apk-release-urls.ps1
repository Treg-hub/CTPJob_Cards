# Shared canonical APK download URLs (Cloud Storage — overwrite in place).
# Dot-source from publish scripts. Do not invent alternate Hosting APK URLs.

$script:ApkStorageBucket = "ctp-job-cards.firebasestorage.app"
$script:ApkGsPrefix = "gs://$script:ApkStorageBucket/releases"

# Firebase Storage public download (rules: releases/** allow read: if true).
function Get-ApkDownloadUrl {
  param([Parameter(Mandatory)][ValidateSet("latest", "pilot")][string]$Name)
  $encoded = [uri]::EscapeDataString("releases/$Name.apk")
  return "https://firebasestorage.googleapis.com/v0/b/$script:ApkStorageBucket/o/$encoded`?alt=media"
}

$script:LatestApkUrl = Get-ApkDownloadUrl -Name latest
$script:PilotApkUrl = Get-ApkDownloadUrl -Name pilot

# Legacy Hosting paths — Hosting redirects these to Storage (bookmarks / old QR).
$script:LegacyLatestHostingUrl = "https://ctp-job-cards-landing.web.app/releases/latest.apk"
$script:LegacyPilotHostingUrl = "https://ctp-job-cards-landing.web.app/releases/pilot.apk"
