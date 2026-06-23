#!/usr/bin/env node
/**
 * Increments the Flutter build number in pubspec.yaml (the +N suffix).
 * Used by githooks/pre-commit so every commit gets a unique build number.
 */
const fs = require('fs');
const path = require('path');

const pubspecPath = path.join(__dirname, '..', 'pubspec.yaml');
const content = fs.readFileSync(pubspecPath, 'utf8');

if (/^<{7}|^={7}|^>{7}/m.test(content)) {
  console.error(
    'bump-build-number: pubspec.yaml has unresolved merge conflict markers — fix before committing',
  );
  process.exit(1);
}

const versionMatches = content.match(/^version:\s*\d+\.\d+\.\d+\+\d+\s*$/gm);
if (!versionMatches || versionMatches.length !== 1) {
  console.error(
    `bump-build-number: expected exactly one version: X.Y.Z+N line (found ${versionMatches?.length ?? 0})`,
  );
  process.exit(1);
}

const match = content.match(/^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$/m);
if (!match) {
  console.error('bump-build-number: expected version: X.Y.Z+N in pubspec.yaml');
  process.exit(1);
}

const [, semver, build] = match;
const nextBuild = Number(build) + 1;
const updated = content.replace(
  /^version:\s*\d+\.\d+\.\d+\+\d+\s*$/m,
  `version: ${semver}+${nextBuild}`,
);

fs.writeFileSync(pubspecPath, updated);
console.log(`bump-build-number: ${semver}+${build} -> ${semver}+${nextBuild}`);