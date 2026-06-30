import 'package:flutter/material.dart';

import '../models/employee.dart';
import '../main.dart'
    show currentEmployee, personaAllowTestSubmissions, personaEmployee, realEmployee;

/// Thrown when a write is attempted in persona mode without test submissions enabled.
class PersonaWriteBlockedException implements Exception {
  @override
  String toString() =>
      'Test submissions are off — enable them in persona mode or stop testing.';
}

bool get isPersonaActive => personaEmployee != null;

bool get canPersonaSubmit => !isPersonaActive || personaAllowTestSubmissions;

/// Firestore write attribution — always the real signed-in employee.
Employee? get writeAttributionEmployee => realEmployee;

/// Effective actor for Firestore writes (real session, never persona).
Employee? resolveWriteActor([Employee? fromProvider]) =>
    writeAttributionEmployee ?? fromProvider ?? currentEmployee;

/// Merge persona audit fields into a Firestore payload.
Map<String, dynamic> withPersonaAudit(Map<String, dynamic> data) =>
    {...data, ...personaAuditFields()};

/// Firestore audit fields when an admin submits while testing as another employee.
Map<String, dynamic> personaAuditFields() {
  if (!isPersonaActive || !personaAllowTestSubmissions) return {};
  final real = realEmployee;
  final persona = personaEmployee;
  if (real == null || persona == null) return {};
  return {
    'submitted_by_clock_no': real.clockNo,
    'submitted_by_name': real.name,
    'acting_as_clock_no': persona.clockNo,
    'acting_as_name': persona.name,
    'persona_test_submission': true,
  };
}

void assertPersonaSubmitAllowed() {
  if (!canPersonaSubmit) throw PersonaWriteBlockedException();
}

/// Returns false and shows a snackbar when persona blocks the write.
bool guardPersonaSubmit(BuildContext context) {
  if (canPersonaSubmit) return true;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Test submissions are off. Enable them in the persona picker or stop testing.',
      ),
    ),
  );
  return false;
}