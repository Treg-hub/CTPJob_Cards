#!/usr/bin/env sh
# Optional: point this clone at tracked githooks (no build-number auto-bump).
# Build numbers are owned by /mobile-app-release and /mobile-pilot-release only.
set -e
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
git config --local core.hooksPath githooks
echo "Git hooks path: $repo_root/githooks"
echo "pre-commit does NOT bump pubspec. Bump only when shipping APKs:"
echo "  node scripts/bump-build-number.js   # then changelog + build"
echo "  Skills: mobile-app-release | mobile-pilot-release"
