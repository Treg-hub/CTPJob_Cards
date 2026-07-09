import '../models/employee.dart';
import 'firestore_service.dart';

/// Session-scoped employee roster for persona picker / assign factory list.
///
/// Loads the full list once and keeps it until [invalidate] (e.g. admin
/// add/remove employee). No TTL — not a presence live feed.
class EmployeeRosterCache {
  EmployeeRosterCache._();
  static final EmployeeRosterCache instance = EmployeeRosterCache._();

  final FirestoreService _service = FirestoreService();
  List<Employee>? _roster;
  Future<List<Employee>>? _inFlight;

  /// Cached roster if already loaded.
  List<Employee>? get cached => _roster;

  bool get isLoaded => _roster != null;

  /// Load once; subsequent calls return the same list until [invalidate].
  Future<List<Employee>> getRoster() {
    if (_roster != null) return Future.value(_roster);
    return _inFlight ??= _load();
  }

  Future<List<Employee>> _load() async {
    try {
      final list = await _service.getAllEmployees();
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _roster = list;
      return list;
    } finally {
      _inFlight = null;
    }
  }

  /// Drop cache (call after admin creates/deletes an employee).
  void invalidate() {
    _roster = null;
    _inFlight = null;
  }

  /// Force reload from server.
  Future<List<Employee>> reload() {
    invalidate();
    return getRoster();
  }
}
