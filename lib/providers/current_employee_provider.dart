import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show personaEmployee, realEmployee;
import '../models/employee.dart';
import '../services/employee_roster_cache.dart';
import '../services/firestore_service.dart';
import 'persona_provider.dart';

final firestoreServiceProvider =
    Provider<FirestoreService>((ref) => FirestoreService());

/// Session-cached full employee roster (persona picker / admin lists).
/// Not a live presence stream — reload via [EmployeeRosterCache.invalidate]
/// when admin adds/removes employees.
final employeesRosterProvider = FutureProvider<List<Employee>>((ref) {
  return EmployeeRosterCache.instance.getRoster();
});

class CurrentEmployeeNotifier extends AsyncNotifier<Employee?> {
  @override
  Future<Employee?> build() async {
    ref.watch(personaProvider);

    if (personaEmployee != null) {
      return personaEmployee;
    }

    if (realEmployee != null) {
      return realEmployee;
    }

    final prefs = await SharedPreferences.getInstance();
    final clockNo = prefs.getString('loggedInClockNo');
    if (clockNo == null) return null;
    final service = ref.read(firestoreServiceProvider);
    realEmployee = await service.getEmployee(clockNo);
    return realEmployee;
  }
}

final currentEmployeeProvider =
    AsyncNotifierProvider<CurrentEmployeeNotifier, Employee?>(
  CurrentEmployeeNotifier.new,
);