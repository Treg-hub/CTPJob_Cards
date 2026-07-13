/**
 * Scrub floor-facing CHANGELOG.md:
 * - Remove ### For admins / Admin / Developer sections
 * - Soften a few known sensitive phrases in remaining body
 * Run: node scripts/scrub-changelog-floor.js
 */
const fs = require('fs');
const path = require('path');

const FILE = path.join(__dirname, '..', 'docs', 'CHANGELOG.md');

function stripAdminSections(markdown) {
  const lines = markdown.split('\n');
  const out = [];
  let skipping = false;
  for (const line of lines) {
    const trimmed = line.trimStart();
    if (trimmed.startsWith('### ')) {
      const title = trimmed.slice(4).toLowerCase();
      skipping =
        title.startsWith('for admins') ||
        title === 'admins' ||
        title.startsWith('admin ') ||
        title === 'admin' ||
        title.startsWith('for developers') ||
        title.startsWith('developer /') ||
        title.startsWith('developers') ||
        title.startsWith('developer / architecture') ||
        title.includes('architecture changes');
      if (skipping) continue;
    } else if (skipping) {
      if (trimmed.startsWith('## ') || trimmed === '---') {
        skipping = false;
      } else {
        continue;
      }
    }
    if (skipping) continue;
    out.push(line);
  }
  return out.join('\n').replace(/\n{3,}/g, '\n\n').trim() + '\n';
}

function softenSensitive(md) {
  return md
    // Drop bare Hosting URLs from staff copy
    .replace(/https?:\/\/ctp-job-cards-landing\.web\.app\/releases\/[^\s)]+/g, 'the official company download')
    .replace(/`?…\/releases\/(?:pilot|latest)\.apk`?/g, 'the official company download')
    .replace(/\*\*Pilot only:\*\*[^\n]*/g, '')
    .replace(/Channel APK URL[^\n]*/gi, '')
    .replace(/Shared download URL[^\n]*/gi, '')
    .replace(/\/mobile-(?:app|pilot)-release/g, '')
    .replace(/docs\/RELEASE_PLAYBOOK\.md/g, '')
    .replace(/docs\/admin_app_update_guide\.md/g, '')
    .replace(/app_secrets/g, 'secure server settings')
    .replace(/copperPassword/g, 'Copper unlock')
    .replace(/registration_locked/g, 'registration lock')
    .replace(/clear_copper_password\.mjs/g, 'admin cleanup script')
    .replace(/clocks?\s*22\s*\/\s*5421\s*\/\s*20/gi, 'authorised Copper users')
    .replace(/clocks?\s*22\s*\+\s*2-3 test users/gi, 'designated pilot users')
    .replace(/\(pilot:\s*clock\s*\d+\)/gi, '(pilot workers)')
    .replace(/clock\s*10338/gi, 'enrolled workers')
    .replace(/mapping\.txt[^\n]*/gi, '')
    .replace(/backfill_fleet_inbox_denorm\.mjs[^\n]*/gi, '')
    .replace(/Firestore_Cost_Discipline\.md[^\n]*/gi, '')
    .replace(/\n{3,}/g, '\n\n');
}

const header = `# CTP Job Cards — Documentation Changelog

What's new in the app. Staff see this after an update (**What's changed**) and under **Settings → Documentation → Changelog**.

Entries are newest-first. When you update from an older build, the app shows every release you missed.

---

`;

let body = fs.readFileSync(FILE, 'utf8');
// Drop old header through first ##
const firstH2 = body.indexOf('\n## ');
if (firstH2 >= 0) {
  body = body.slice(firstH2 + 1);
} else if (body.startsWith('## ')) {
  // already starts at first entry
} else {
  console.error('No ## entries found');
  process.exit(1);
}

body = stripAdminSections(body);
body = softenSensitive(body);
fs.writeFileSync(FILE, header + body);
console.log('Scrubbed', FILE);
