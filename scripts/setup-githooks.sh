#!/usr/bin/env sh
# Enable tracked git hooks for this clone (run once after clone).
set -e
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
git config --local core.hooksPath githooks
echo "Git hooks enabled: $repo_root/githooks (pre-commit bumps pubspec build number)"