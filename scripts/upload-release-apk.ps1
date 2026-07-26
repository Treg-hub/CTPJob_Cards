# Upload a release APK to Cloud Storage (stable object path, overwrite in place).
# Bypasses Storage rules via ADC / gcloud (client write is denied).
#
# Usage (from mobile/CTPJob_Cards):
#   pwsh .\scripts\upload-release-apk.ps1 -Name latest
#   pwsh .\scripts\upload-release-apk.ps1 -Name pilot -ApkPath .\build\app\outputs\flutter-apk\app-release.apk
#
# Canonical URLs: see apk-release-urls.ps1

param(
  [Parameter(Mandatory)]
  [ValidateSet("latest", "pilot")]
  [string]$Name,

  [string]$ApkPath = ""
)

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$AppRoot = Get-Location

. (Join-Path $PSScriptRoot "apk-release-urls.ps1")

if (-not $ApkPath) {
  $ApkPath = Join-Path $AppRoot "build\app\outputs\flutter-apk\app-release.apk"
}
if (-not (Test-Path $ApkPath)) {
  Write-Error "APK not found at $ApkPath"
}

$apkItem = Get-Item $ApkPath
$pubspecItem = Get-Item (Join-Path $AppRoot "pubspec.yaml")
if ($apkItem.LastWriteTimeUtc -lt $pubspecItem.LastWriteTimeUtc.AddMinutes(-1)) {
  Write-Error ("APK is older than pubspec.yaml ({0:u} < {1:u}). " +
    "Rebuild before upload — refusing to publish a stale binary as {2}.apk.") -f `
    $apkItem.LastWriteTimeUtc, $pubspecItem.LastWriteTimeUtc, $Name
}

$dest = "$script:ApkGsPrefix/$Name.apk"
$url = Get-ApkDownloadUrl -Name $Name

Write-Host "==> Upload $Name.apk → $dest" -ForegroundColor Cyan
Write-Host ("    Source: {0:N1} MB, {1:g}" -f ($apkItem.Length / 1MB), $apkItem.LastWriteTime)

# Prefer gcloud storage cp (ADC). Short cache so floor clients pick up overwrites.
& gcloud storage cp $ApkPath $dest `
  --project=ctp-job-cards `
  --cache-control="public, max-age=300" `
  --content-type="application/vnd.android.package-archive"
if ($LASTEXITCODE -ne 0) {
  Write-Error "gcloud storage cp failed (exit $LASTEXITCODE). Ensure ADC / gcloud auth for ctp-job-cards."
}

Write-Host "    Verifying public download URL (Content-Length)..." -ForegroundColor DarkGray
$head = & curl.exe -sI $url
if ($LASTEXITCODE -ne 0) {
  Write-Error "curl HEAD failed for $url"
}
$lenLine = ($head | Select-String -Pattern '(?i)^content-length:\s*(\d+)' | Select-Object -First 1)
if (-not $lenLine) {
  Write-Host $head
  Write-Error "No Content-Length from Storage URL — check Storage rules deploy + object path."
}
$got = [long]$lenLine.Matches[0].Groups[1].Value
if ($got -lt 1MB) {
  Write-Error "Download URL Content-Length is only $got bytes — check Storage rules deploy + object path."
}
Write-Host ("    OK — Content-Length {0:N1} MB" -f ($got / 1MB)) -ForegroundColor Green

Write-Host ""
Write-Host "Canonical download URL:" -ForegroundColor Green
Write-Host "  $url"
