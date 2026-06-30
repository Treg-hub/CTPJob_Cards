import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/security_gate.dart';
import '../models/security_settings.dart';
import '../models/security_vehicle.dart';
import '../services/security_service.dart';

final _securityService = SecurityService();

final securitySettingsProvider = StreamProvider<SecuritySettings>((ref) {
  return _securityService.watchSettings();
});

final securityGatesProvider = StreamProvider<List<SecurityGate>>((ref) {
  return _securityService.watchGates(activeOnly: true);
});

/// Persists the guard's chosen gate in SharedPreferences so it survives
/// leaving Security, app restarts, and tab switches.
class SelectedSecurityGateNotifier extends Notifier<SecurityGate?> {
  static const _prefsKey = 'selectedSecurityGateId';

  @override
  SecurityGate? build() {
    ref.listen<AsyncValue<List<SecurityGate>>>(
      securityGatesProvider,
      (_, next) => next.whenData(_applyGateList),
      fireImmediately: true,
    );
    _loadSavedGateId();
    return null;
  }

  Future<void> _loadSavedGateId() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_prefsKey);
    if (savedId == null) return;
    final gates = ref.read(securityGatesProvider).valueOrNull;
    if (gates != null) _applyGateList(gates, preferredId: savedId);
  }

  void _applyGateList(List<SecurityGate> gates, {String? preferredId}) {
    if (gates.isEmpty) {
      if (state != null) state = null;
      return;
    }

    final targetId = preferredId ?? state?.id;
    if (targetId != null) {
      final match = _findGate(gates, targetId);
      if (match != null) {
        if (state?.id != match.id) state = match;
        return;
      }
      if (preferredId != null) {
        _clearPrefs();
      }
    }

    if (state == null && gates.length == 1) {
      state = gates.first;
      _persist(gates.first.id);
    }
  }

  SecurityGate? _findGate(List<SecurityGate> gates, String id) {
    for (final gate in gates) {
      if (gate.id == id) return gate;
    }
    return null;
  }

  Future<void> select(SecurityGate? gate) async {
    state = gate;
    if (gate != null) {
      await _persist(gate.id);
    } else {
      await _clearPrefs();
    }
  }

  Future<void> _persist(String gateId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, gateId);
  }

  Future<void> _clearPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}

final selectedSecurityGateProvider =
    NotifierProvider<SelectedSecurityGateNotifier, SecurityGate?>(
  SelectedSecurityGateNotifier.new,
);

final securityServiceProvider = Provider<SecurityService>((ref) {
  return _securityService;
});

final securityVehiclesProvider = StreamProvider<List<SecurityVehicle>>((ref) {
  return _securityService.watchVehicles(activeOnly: true);
});