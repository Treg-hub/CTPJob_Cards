// background_geofence_service.dart
// Thin wrapper – real logic lives in LocationService

import 'location_service.dart';

class BackgroundGeofenceService {
  static final BackgroundGeofenceService _instance = BackgroundGeofenceService._internal();
  factory BackgroundGeofenceService() => _instance;
  BackgroundGeofenceService._internal();

  final LocationService _locationService = LocationService();

  Future<void> initialize() async {
    // No-op – initialization happens in LocationService
  }

  Future<void> startMonitoring(String clockNo) async {
    await _locationService.startNativeMonitoring(clockNo);
  }

  Future<void> stopMonitoring() async {
    await _locationService.stopNativeMonitoring();
  }
}