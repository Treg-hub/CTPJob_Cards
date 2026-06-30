"""Add resolveWriteActor for Firestore write attribution in module screens."""
import re
from pathlib import Path

SCREENS = Path(__file__).resolve().parent.parent / "lib" / "screens"

# Per-file: after `final emp = currentEmployee` / similar, inject actor + swap clock fields in service calls.
PATCHES = {
    "fleet_report_wizard_screen.dart": [
        (
            "    final emp = currentEmployee;\n    if (emp == null) return;\n",
            "    final emp = currentEmployee;\n    if (emp == null) return;\n    final actor = resolveWriteActor(emp)!;\n",
        ),
        ("reportedByClockNo: emp.clockNo", "reportedByClockNo: actor.clockNo"),
        ("reportedByName: emp.name", "reportedByName: actor.name"),
    ],
    "fleet_daily_check_screen.dart": [
        (
            "    final emp = currentEmployee;\n    if (emp == null) return;\n",
            "    final emp = currentEmployee;\n    if (emp == null) return;\n    final actor = resolveWriteActor(emp)!;\n",
        ),
        ("driverClockNo: emp.clockNo", "driverClockNo: actor.clockNo"),
        ("reportedByClockNo: emp.clockNo", "reportedByClockNo: actor.clockNo"),
        ("reportedByName: emp.name", "reportedByName: actor.name"),
    ],
    "fleet_log_other_work_screen.dart": [
        (
            "    final emp = currentEmployee;\n    if (emp == null) return;\n",
            "    final emp = currentEmployee;\n    if (emp == null) return;\n    final actor = resolveWriteActor(emp)!;\n",
        ),
        ("'logged_by_clock_no': emp.clockNo", "'logged_by_clock_no': actor.clockNo"),
        ("loggedByClockNo: emp.clockNo", "loggedByClockNo: actor.clockNo"),
        ("loggedByName: emp.name", "loggedByName: actor.name"),
    ],
    "fleet_mark_fixed_screen.dart": [
        (
            "    final emp = currentEmployee;\n    if (emp == null) return;\n",
            "    final emp = currentEmployee;\n    if (emp == null) return;\n    final actor = resolveWriteActor(emp)!;\n",
        ),
        ("emp.clockNo, emp.name", "actor.clockNo, actor.name"),
        ("'logged_by_clock_no': emp.clockNo", "'logged_by_clock_no': actor.clockNo"),
        ("loggedByClockNo: emp.clockNo", "loggedByClockNo: actor.clockNo"),
        ("loggedByName: emp.name", "loggedByName: actor.name"),
    ],
    "fleet_issue_detail_screen.dart": [
        (
            "    final emp = currentEmployee;\n    if (emp == null) return;\n",
            "    final emp = currentEmployee;\n    if (emp == null) return;\n    final actor = resolveWriteActor(emp)!;\n",
        ),
        ("emp.clockNo, emp.name", "actor.clockNo, actor.name"),
    ],
    "fleet_work_record_detail_screen.dart": [
        (
            "    final emp = currentEmployee;\n    if (emp == null) return;\n",
            "    final emp = currentEmployee;\n    if (emp == null) return;\n    final actor = resolveWriteActor(emp)!;\n",
        ),
        ("authorClockNo: emp.clockNo", "authorClockNo: actor.clockNo"),
        ("authorName: emp.name", "authorName: actor.name"),
    ],
    "copper_dashboard_screen.dart": [
        (
            "    final employee = ref.read(currentEmployeeProvider).valueOrNull;\n    if (employee == null) return;\n",
            "    final employee = ref.read(currentEmployeeProvider).valueOrNull;\n    if (employee == null) return;\n    final actor = resolveWriteActor(employee)!;\n",
        ),
        ("employee.clockNo", "actor.clockNo"),
    ],
    "waste_begin_collection_screen.dart": [
        (
            "collectedBy: currentEmployee?.clockNo ?? ''",
            "collectedBy: resolveWriteActor(currentEmployee)?.clockNo ?? ''",
        ),
        (
            "collectedByName: currentEmployee?.name",
            "collectedByName: resolveWriteActor(currentEmployee)?.name",
        ),
    ],
    "waste_load_detail_screen.dart": [
        (
            "finishedBy: currentEmployee?.clockNo ?? ''",
            "finishedBy: resolveWriteActor(currentEmployee)?.clockNo ?? ''",
        ),
        (
            "finishedByName: currentEmployee?.name",
            "finishedByName: resolveWriteActor(currentEmployee)?.name",
        ),
        (
            "collectedBy: currentEmployee?.clockNo",
            "collectedBy: resolveWriteActor(currentEmployee)?.clockNo",
        ),
        (
            "collectedByName: currentEmployee?.name",
            "collectedByName: resolveWriteActor(currentEmployee)?.name",
        ),
    ],
    "waste_create_load_screen.dart": [
        ("actorClockNo: currentEmployee?.clockNo", "actorClockNo: resolveWriteActor(currentEmployee)?.clockNo"),
    ],
    "waste_schedule_load_screen.dart": [
        ("scheduledBy: employee?.clockNo ?? ''", "scheduledBy: resolveWriteActor(employee)?.clockNo ?? ''"),
    ],
    "waste_add_stock_item_screen.dart": [
        ("createdBy: currentEmployee?.clockNo ?? ''", "createdBy: resolveWriteActor(currentEmployee)?.clockNo ?? ''"),
    ],
    "security_add_cost_screen.dart": [
        ("enteredByClockNo: emp.clockNo", "enteredByClockNo: resolveWriteActor(emp)!.clockNo"),
    ],
}

IMPORT = "import '../utils/persona_audit.dart';\n"

for fname, replacements in PATCHES.items():
    path = SCREENS / fname
    if not path.exists():
        print("skip missing", fname)
        continue
    text = path.read_text(encoding="utf-8")
    orig = text
    if "resolveWriteActor" not in text and IMPORT.strip() not in text:
        if "package:flutter/material.dart" in text:
            text = text.replace(
                "import 'package:flutter/material.dart';\n",
                "import 'package:flutter/material.dart';\n" + IMPORT,
                1,
            )
        elif "package:flutter_riverpod/flutter_riverpod.dart" in text:
            text = text.replace(
                "import 'package:flutter_riverpod/flutter_riverpod.dart';\n",
                "import 'package:flutter_riverpod/flutter_riverpod.dart';\n" + IMPORT,
                1,
            )
    for old, new in replacements:
        if old not in text:
            print("WARN missing pattern in", fname, repr(old[:50]))
        text = text.replace(old, new)
    if text != orig:
        path.write_text(text, encoding="utf-8")
        print("patched attribution", fname)