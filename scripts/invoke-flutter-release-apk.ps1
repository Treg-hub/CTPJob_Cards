# Build the arm64 release APK with a stable Gradle cache.
#
# Cursor's default sandbox remaps Gradle into
#   %TEMP%\cursor-sandbox-cache\...\gradle
# with caching off. assembleRelease then looks hung (no progress for 15+ min).
# Pin GRADLE_USER_HOME to the real user cache and use a plain Gradle console
# so progress lines flush in agent terminals.
#
# Dot-sourced or invoked from publish-landing-*.ps1 when -BuildApk is set.
# Can also be run alone from mobile/CTPJob_Cards:
#   pwsh .\scripts\invoke-flutter-release-apk.ps1

$ErrorActionPreference = "Stop"

if (-not $env:GRADLE_USER_HOME -or [string]::IsNullOrWhiteSpace($env:GRADLE_USER_HOME)) {
  $env:GRADLE_USER_HOME = Join-Path $env:USERPROFILE ".gradle"
}

if ($env:GRADLE_USER_HOME -match 'cursor-sandbox-cache') {
  Write-Error @"
GRADLE_USER_HOME is the Cursor sandbox cache:
  $($env:GRADLE_USER_HOME)
Stop this run. Rebuild with:
  `$env:GRADLE_USER_HOME = Join-Path `$env:USERPROFILE '.gradle'
  flutter build apk --target-platform android-arm64 --release
Then publish without -BuildApk.
"@
}

if (-not (Test-Path $env:GRADLE_USER_HOME)) {
  New-Item -ItemType Directory -Path $env:GRADLE_USER_HOME -Force | Out-Null
}

$opts = [string]$env:GRADLE_OPTS
if ($opts -notmatch 'org\.gradle\.console') {
  $env:GRADLE_OPTS = (($opts, '-Dorg.gradle.console=plain') | Where-Object { $_ -and $_.Trim() }) -join ' '
}

Write-Host "    GRADLE_USER_HOME=$($env:GRADLE_USER_HOME)" -ForegroundColor DarkGray
Write-Host "==> Building release APK (arm64)..." -ForegroundColor Cyan
flutter build apk --target-platform android-arm64 --release
if ($LASTEXITCODE -ne 0) {
  Write-Error "flutter build apk failed (exit $LASTEXITCODE). Not publishing."
}
