#!/usr/bin/env node
/**
 * Increments the Flutter build number in pubspec.yaml (the +N suffix).
 * Used by githooks/pre-commit so every commit gets a unique build number.
 */
const fs = require('fs');
const path = require('path');

const pubspecPath = path.join(__dirname, '..', 'pubspec.yaml');
const content = fs.readFileSync(pubspecPath, 'utf8');

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