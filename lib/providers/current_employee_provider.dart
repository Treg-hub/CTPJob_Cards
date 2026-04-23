import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/employee.dart';
import '../services/firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

final firestoreServiceProvider = Provider<FirestoreService>((ref) => FirestoreService());

class CurrentEmployeeNotifier extends AsyncNotifier<Employee?> {
  @override
  Future<Employee?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final clockNo = prefs.getString('loggedInClockNo');
    if (clockNo == null) return null;
    final service = ref.read(firestoreServiceProvider);
    return service.getEmployee(clockNo);
  }
}

final currentEmployeeProvider = AsyncNotifierProvider<CurrentEmployeeNotifier, Employee?>(() => CurrentEmployeeNotifier());
