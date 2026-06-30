import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show personaAllowTestSubmissions, personaEmployee, realEmployee;
import '../models/employee.dart';

/// UI-only role testing overlay — in-memory only (clears on app restart).
class PersonaState {
  const PersonaState({
    this.employee,
    this.allowTestSubmissions = false,
  });

  final Employee? employee;
  final bool allowTestSubmissions;

  bool get isActive => employee != null;

  static const empty = PersonaState();
}

class PersonaNotifier extends StateNotifier<PersonaState> {
  PersonaNotifier() : super(PersonaState.empty);

  void start(Employee employee, {required bool allowTestSubmissions}) {
    personaEmployee = employee;
    personaAllowTestSubmissions = allowTestSubmissions;
    state = PersonaState(
      employee: employee,
      allowTestSubmissions: allowTestSubmissions,
    );
  }

  void stop() {
    personaEmployee = null;
    personaAllowTestSubmissions = false;
    state = PersonaState.empty;
  }
}

final personaProvider =
    StateNotifierProvider<PersonaNotifier, PersonaState>((ref) {
  return PersonaNotifier();
});

/// Effective employee for UI gating — persona overlay or real session.
final effectiveEmployeeProvider = Provider<Employee?>((ref) {
  ref.watch(personaProvider);
  return personaEmployee ?? realEmployee;
});