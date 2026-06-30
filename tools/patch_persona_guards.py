import re
from pathlib import Path

SCREENS = Path(__file__).resolve().parent.parent / "lib" / "screens"
# Methods that perform writes — matched at start of Future<void> name.
SUBMIT_NAMES = re.compile(
    r"Future<void> (_(?:save|submit|complete|start|finish|send|create|add|delete|append|record|void|mark|acknowledge|resolve|cancel|log|scan|consume|transfer|close|reopen|approve|cost|plate|sort|sale|use|execute|edit|enter|finalise|reissue|reopen|confirm|update|remove|assign|unassign|adjust|change|upload|queue|soft|set|toggle|enable|disable|register|receive|adjustment)[A-Za-z0-9_]*)"
)
GUARD = "    if (!guardPersonaSubmit(context)) return;\n"
IMPORT = "import '../utils/persona_audit.dart';\n"
SKIP_FILES = {"login_screen.dart", "splash_screen.dart"}

for path in sorted(SCREENS.glob("*.dart")):
    if path.name in SKIP_FILES:
        continue
    text = path.read_text(encoding="utf-8")
    orig = text
    if IMPORT.strip() not in text and "package:flutter/material.dart" in text:
        text = text.replace(
            "import 'package:flutter/material.dart';\n",
            "import 'package:flutter/material.dart';\n" + IMPORT,
            1,
        )
    lines = text.splitlines(keepends=True)
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        if SUBMIT_NAMES.search(line) and "async {" in line:
            j = i + 1
            while j < len(lines) and lines[j].strip() == "":
                out.append(lines[j])
                j += 1
            if j < len(lines) and "guardPersonaSubmit" not in lines[j]:
                out.append(GUARD)
        i += 1
    new = "".join(out)
    if new != orig:
        path.write_text(new, encoding="utf-8")
        print("patched", path.name)