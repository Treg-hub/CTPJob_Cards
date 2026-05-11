import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:shared_preferences/shared_preferences.dart';
import 'firestore_service.dart';
import 'notification_service.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  String? _clockNo;
  final FirestoreService _firestoreService = FirestoreService();
  final NotificationService _notificationService = NotificationService();

  bool _isInitialized = false;

  // ==================== START TRACKING ====================
  Future<void> startNativeMonitoring(String clockNo) async {
    if (kIsWeb) return;
    if (_isInitialized) return;

    _clockNo = clockNo;
    await _requestPermissions();
    await _notificationService.initialize();

    try {
      await bg.BackgroundGeolocation.ready(bg.Config(
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_LOW,
        distanceFilter: 200,
        stationaryRadius: 150,
        stopTimeout: 30,
        heartbeatInterval: 30,
        stopOnTerminate: false,
        startOnBoot: true,
        debug: false,
        logLevel: bg.Config.LOG_LEVEL_ERROR,
        geofenceProximityRadius: 800,
        geofenceInitialTriggerEntry: true,
        notifyOnEntry: true,
        notifyOnExit: true,
      ));

      await bg.BackgroundGeolocation.addGeofence(bg.Geofence(
        identifier: "company_site",
        latitude: -29.994938052011612,
        longitude: 30.939421740548614,
        radius: 800,
        notifyOnEntry: true,
        notifyOnExit: true,
      ));

      bg.BackgroundGeolocation.onGeofence(_handleGeofenceEvent);
      bg.BackgroundGeolocation.onLocation(_handleLocationUpdate);

      await bg.BackgroundGeolocation.start();
      _isInitialized = true;

      debugPrint('✅ Background Geolocation started for $clockNo (Ultra Low Battery Mode)');
    } catch (e) {
      debugPrint('Background Geolocation failed: $e');
    }
  }

  Future<void> stopNativeMonitoring() async {
    if (kIsWeb) return;
    await bg.BackgroundGeolocation.stop();
    _isInitialized = false;
    debugPrint('🛑 Background Geolocation stopped');
  }

  // ==================== EVENT HANDLERS ====================
  void _handleGeofenceEvent(bg.GeofenceEvent event) async {
    final isEntering = event.action == bg.GeofenceEvent.ENTER;
    final eventType = isEntering ? 'enter' : 'exit';

    await _logGeoFenceEvent(
      eventType: eventType,
      source: 'flutter_bg_geofence',
    );
    await _updateFirestore(isEntering);
    await _sendNotification(isEntering);
  }

  void _handleLocationUpdate(bg.Location location) {
    debugPrint('📍 Location update received');
  }

  // ==================== LOGGING & HELPERS (Kept from your current code) ====================
  Future<void> _logGeoFenceEvent({
    required String eventType,
    required String source,
    double? latitude,
    double? longitude,
    double? accuracy,
    String? notes,
  }) async {
    if (_clockNo == null) {
      final prefs = await SharedPreferences.getInstance();
      _clockNo = prefs.getString('loggedInClockNo');
    }
    if (_clockNo == null) return;

    await _firestoreService.logGeoFenceEvent(
      clockNo: _clockNo!,
      eventType: eventType,
      source: source,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      notes: notes,
    );
  }

  Future<void> logTestGeoFenceEvent({required bool isEntering, String? notes}) async {
    final prefs = await SharedPreferences.getInstance();
    final clockNo = prefs.getString('loggedInClockNo') ?? 'UNKNOWN';

    await _logGeoFenceEvent(
      eventType: isEntering ? 'enter' : 'exit',
      source: 'manual_test',
      notes: notes ?? 'Manual test from Diagnostics screen',
    );
    await _updateFirestore(isEntering);
    await _sendNotification(isEntering);
  }

  Future<void> _updateFirestore(bool onSite) async {
    if (_clockNo == null) return;
    final emp = await _firestoreService.getEmployee(_clockNo!);
    if (emp != null) {
      await _firestoreService.updateEmployee(emp.copyWith(isOnSite: onSite));
    }
  }

  Future<void> _sendNotification(bool onSite) async {
    final title = onSite ? '✅ On-Site Detected' : '📍 Left Site Area';
    final body = onSite ? 'You are within the company radius.' : 'You have left the site area.';
    await _notificationService.showOnSiteNotification(title: title, body: body);
  }

  Future<void> _requestPermissions() async {
    // Permissions are mostly handled by the package + your existing code
  }

  // Keep this for backward compatibility
  Future<void> checkCurrentLocation() async {
    // You can leave this empty or implement a manual check if needed
  }
}