// Assembles the landing-deploy/ directory that Firebase Hosting serves for the
// `landing` target. Copies:
//   landing/index.html         → landing-deploy/index.html
//   docs/**                    → landing-deploy/docs/**       (only the cleaned, employee-safe set)
//   assets/images/logo.png     → landing-deploy/assets/images/logo.png
//
// Run before `firebase deploy --only hosting:landing`.

const fs = require('fs');
const path = require('path');

const ROOT = __dirname;
const OUT  = path.join(ROOT, 'landing-deploy');

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
// Defence in depth: even though the dev-only docs were moved to dev-docs/,
// this filter explicitly excludes anything that should never reach the web.
const DOC_BLOCKLIST = new Set([
  'firebase_security_rules.html',
  'firebase_security_rules.md',
  'firebase_security_rules.pdf',
  'cloud_functions_deployment.html',
  'cloud_functions_deployment.md',
  'cloud_functions_deployment.pdf',
]);

copyDir(
  path.join(ROOT, 'docs'),
  path.join(OUT, 'docs'),
  (src, entry) => {
    if (entry.isDirectory() && entry.name === 'architecture') return false;
    if (entry.isDirectory() && entry.name.startsWith('.')) return false;
    if (entry.isFile() && DOC_BLOCKLIST.has(entry.name)) return false;
    return true;
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

console.log(`landing-deploy/ assembled — ${countFiles(OUT)} files`);
console.log(`  index.html       → 1`);
console.log(`  assets/          → ${countFiles(path.join(OUT, 'assets'))}`);
console.log(`  docs/            → ${countFiles(path.join(OUT, 'docs'))}`);
console.log('');
console.log('Next: firebase deploy --only hosting:landing');
