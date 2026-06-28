import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final selectedSecurityGateProvider = StateProvider<SecurityGate?>((ref) => null);

final securityServiceProvider = Provider<SecurityService>((ref) {
  return _securityService;
});

final securityVehiclesProvider = StreamProvider<List<SecurityVehicle>>((ref) {
  return _securityService.watchVehicles(activeOnly: true);
});