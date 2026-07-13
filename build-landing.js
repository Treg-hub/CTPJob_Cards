// Assembles the landing-deploy/ directory that Firebase Hosting serves for the
// `landing` target. Copies:
//   landing/index.html         → landing-deploy/index.html
//   docs/**                    → landing-deploy/docs/**       (only the cleaned, employee-safe set)
//   assets/images/logo.png     → landing-deploy/assets/images/logo.png
//   build/.../app-release.apk  → landing-deploy/releases/latest.apk  (if present)
//
// IMPORTANT: this script wipes landing-deploy/ then rebuilds it. The APK is
// copied at the END if a release build exists. Order for a full release:
//   1. flutter build apk --target-platform android-arm64 --release
//   2. node build-landing.js
//   3. firebase deploy --only hosting:landing --project ctp-job-cards
//
// Official download URL (also Admin Shared download URL for in-app updates):
//   https://ctp-job-cards-landing.web.app/releases/latest.apk

const fs = require('fs');
const path = require('path');

const ROOT = __dirname;
const OUT  = path.join(ROOT, 'landing-deploy');
const APK_SRC = path.join(
  ROOT,
  'build',
  'app',
  'outputs',
  'flutter-apk',
  'app-release.apk',
);
const APK_DEST = path.join(OUT, 'releases', 'latest.apk');

function rmrf(p) {
  if (fs.existsSync(p)) fs.rmSync(p, { recursive: true, force: true });
}

function mkdirp(p) {
  fs.mkdirSync(p, { recursive: true });
}

function copyFile(from, to) {
  mkdirp(path.dirname(to));
  fs.copyFileSync(from, to);
}

function copyDir(from, to, filter = () => true) {
  if (!fs.existsSync(from)) return;
  for (const entry of fs.readdirSync(from, { withFileTypes: true })) {
    const src = path.join(from, entry.name);
    const dst = path.join(to, entry.name);
    if (!filter(src, entry)) continue;
    if (entry.isDirectory()) copyDir(src, dst, filter);
    else copyFile(src, dst);
  }
}

// ─── Clean output ───────────────────────────────────────────────────────────
rmrf(OUT);
mkdirp(OUT);

// ─── Landing page ───────────────────────────────────────────────────────────
copyFile(path.join(ROOT, 'landing', 'index.html'), path.join(OUT, 'index.html'));

// ─── Logo ────────────────────────────────────────────────────────────────────
copyFile(
  path.join(ROOT, 'assets', 'images', 'logo.png'),
  path.join(OUT, 'assets', 'images', 'logo.png'),
);

// ─── Docs ────────────────────────────────────────────────────────────────────
// Allowlist only — never publish playbooks, admin update guides, pilot checklists,
// or engineering refs to public Hosting (defence in depth vs APK bundling).
const DOC_ALLOWLIST = new Set([
  'CHANGELOG.md',
  'employee_guide.md',
  'manager_guide.md',
  'executive_overview.md',
  'app_features.md',
  'troubleshooting.md',
  'waste_user_guide.md',
  'fleet_user_guide.md',
  'fleet_mechanic_guide.md',
  'fleet_reporter_guide.md',
  'security_guard_guide.md',
  'security_manager_mobile_guide.md',
]);

copyDir(
  path.join(ROOT, 'docs'),
  path.join(OUT, 'docs'),
  (src, entry) => {
    if (entry.isDirectory()) return false; // no nested folders on public landing
    if (entry.isFile() && entry.name.startsWith('.')) return false;
    return DOC_ALLOWLIST.has(entry.name);
  },
);

// ─── Summary ─────────────────────────────────────────────────────────────────
function countFiles(p) {
  let n = 0;
  if (!fs.existsSync(p)) return 0;
  for (const e of fs.readdirSync(p, { withFileTypes: true })) {
    n += e.isDirectory() ? countFiles(path.join(p, e.name)) : 1;
  }
  return n;
}

// ─── Official APK (optional — only if a release APK was built) ─────────────
let apkCopied = false;
if (fs.existsSync(APK_SRC)) {
  copyFile(APK_SRC, APK_DEST);
  const sizeMb = (fs.statSync(APK_DEST).size / (1024 * 1024)).toFixed(1);
  apkCopied = true;
  console.log(`  releases/latest.apk ← app-release.apk (${sizeMb} MB)`);
} else {
  console.warn(
    '  releases/latest.apk  SKIPPED — no build/app/outputs/flutter-apk/app-release.apk',
  );
  console.warn(
    '    Build the APK first, then re-run this script before deploy, or copy manually.',
  );
}

console.log(`landing-deploy/ assembled — ${countFiles(OUT)} files`);
console.log(`  index.html       → 1`);
console.log(`  assets/          → ${countFiles(path.join(OUT, 'assets'))}`);
console.log(`  docs/            → ${countFiles(path.join(OUT, 'docs'))}`);
console.log(`  releases/apk     → ${apkCopied ? 'yes' : 'NO'}`);
console.log('');
console.log('Next: firebase deploy --only hosting:landing --project ctp-job-cards');
console.log(
  'URL:  https://ctp-job-cards-landing.web.app/releases/latest.apk',
);
