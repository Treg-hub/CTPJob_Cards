"""Remove incorrect persona guards and unused imports from over-patched screens."""
from pathlib import Path

SCREENS = Path(__file__).resolve().parent.parent / "lib" / "screens"
IMPORT_LINE = "import '../utils/persona_audit.dart';\n"
GUARD_LINE = "    if (!guardPersonaSubmit(context)) return;\n"

# Methods that must NOT have persona submit guards.
REMOVE_GUARD_IN = {
    "home_screen.dart": {
        "_setupFirebaseMessaging",
        "_saveShowDeptOnly",
        "_saveTestMode",
        "_disableTestMode",
    },
    "notification_inbox_screen.dart": {"_markRead", "_markAllRead"},
    "settings_screen.dart": {"_logout"},
    "registration_screen.dart": {"_register"},
    "permissions_onboarding_screen.dart": {"_completeOnboarding"},
}

for fname, methods in REMOVE_GUARD_IN.items():
    path = SCREENS / fname
    if not path.exists():
        continue
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        matched = any(f"Future<void> {m}(" in line for m in methods)
        if matched and "async {" in line:
            if i + 1 < len(lines) and lines[i + 1].strip() == GUARD_LINE.strip():
                i += 1  # skip guard line
        i += 1
    path.write_text("".join(out), encoding="utf-8")
    print("fixed guards in", fname)

# Remove unused persona_audit imports (no guard/resolve/writeAttribution usage).
for path in sorted(SCREENS.glob("*.dart")):
    text = path.read_text(encoding="utf-8")
    if IMPORT_LINE.strip() not in text:
        continue
    uses = any(
        s in text
        for s in (
            "guardPersonaSubmit",
            "resolveWriteActor",
            "writeAttributionEmployee",
            "withPersonaAudit",
            "personaAuditFields",
            "assertPersonaSubmitAllowed",
        )
    )
    if not uses:
        text = text.replace(IMPORT_LINE, "")
        path.write_text(text, encoding="utf-8")
        print("removed unused import", path.name)