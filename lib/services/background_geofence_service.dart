// background_geofence_service.dart
// Stub file to prevent build errors. Real geofence logic is in location_service.dart + native code.

import 'dart:async';
import 'package:flutter/foundation.dart';

class BackgroundGeofenceService {
  static final BackgroundGeofenceService _instance = BackgroundGeofenceService._internal();
  factory BackgroundGeofenceService() => _instance;
  BackgroundGeofenceService._internal();

  Future<void> initialize() async {
    if (kIsWeb) {
      debugPrint('📍 Background geofence not supported on web');
      return;
    }
    debugPrint('📍 BackgroundGeofenceService initialized (stub)');
  }

  Future<void> startMonitoring(String clockNo) async {
    debugPrint('📍 Background monitoring started for $clockNo (stub)');
  }

  Future<void> stopMonitoring() async {
    debugPrint('📍 Background monitoring stopped (stub)');
  }
}