import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';
import 'firestore_service.dart';
import 'notification_service.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static const double COMPANY_LAT = -29.994938052011612;
  static const double COMPANY_LON = 30.939421740548614;
  static const double RADIUS_METERS = 800.0;

  final MethodChannel _channel = const MethodChannel('ctp/geofence');
  String? _clockNo;
  final FirestoreService _firestoreService = FirestoreService();
  final NotificationService _notificationService = NotificationService();

  Timer? _onSiteRecheckTimer;

  // ==================== START / STOP (preserved from current structure) ====================
  Future<void> startNativeMonitoring(String clockNo) async {
    if (kIsWeb) return;
    _clockNo = clockNo;
    await _requestPermissions();
    await _notificationService.initialize();

    try {
      await _channel.invokeMethod('registerGeofence', {
        'clockNo': clockNo,
        'lat': COMPANY_LAT,
        'lng': COMPANY_LON,
        'radius': RADIUS_METERS,
      });
      debugPrint('✅ Geofence registered for $clockNo');
    } catch (e) {
      debugPrint('Geofence registration failed: $e');
    }
    await _checkFallback();
  }

  Future<void> stopNativeMonitoring() async {
    if (kIsWeb) return;
    await _channel.invokeMethod('stopGeofence');
    _stopOnSiteRecheckTimer();
  }

  // ==================== EVENT HANDLING (adapted) ====================
  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onGeofenceEvent') {
      final isEntering = call.arguments['entering'] as bool;
      final eventType = isEntering ? 'enter' : 'exit';

      await _logGeoFenceEvent(
        eventType: eventType,
        source: 'native_geofence',
      );
      await _updateFirestore(isEntering);
      await _sendNotification(isEntering);

      if (isEntering) {
        _startOnSiteRecheckTimer();
      } else {
        _stopOnSiteRecheckTimer();
      }
    }
  }

  // ==================== FALLBACK + BACKGROUND + LOGGING ====================
  Future<void> _checkFallback() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        final onSite = Geolocator.distanceBetween(COMPANY_LAT, COMPANY_LON, pos.latitude, pos.longitude) <= RADIUS_METERS;
        await _logGeoFenceEvent(
          eventType: onSite ? 'enter' : 'exit',
          source: 'fallback',
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracy: pos.accuracy,
        );
        await _updateFirestore(onSite);
      }
    } catch (e) {}
  }

  Future<void> backgroundCheck() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clockNo = prefs.getString('loggedInClockNo');
      if (clockNo == null) return;

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      final onSite = Geolocator.distanceBetween(COMPANY_LAT, COMPANY_LON, pos.latitude, pos.longitude) <= RADIUS_METERS;

      if (!onSite) {
        await _logGeoFenceEvent(
          eventType: 'exit',
          source: 'background_check',
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracy: pos.accuracy,
        );
        await _updateFirestore(false);
      }
    } catch (e) {}
  }

  // ==================== LOGGING HELPER (NEW) ====================
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

  // ==================== MANUAL TEST METHOD ====================
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

  // ... (rest of methods like _updateFirestore, _sendNotification, _requestPermissions, timers, checkCurrentLocation, etc. preserved from current structure)
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

  void _startOnSiteRecheckTimer() {
    _stopOnSiteRecheckTimer();
    _onSiteRecheckTimer = Timer.periodic(const Duration(minutes: 30), (timer) async {
      await backgroundCheck();
    });
  }

  void _stopOnSiteRecheckTimer() {
    _onSiteRecheckTimer?.cancel();
    _onSiteRecheckTimer = null;
  }

  Future<void> _requestPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return;

    await ph.Permission.locationAlways.request();
  }

  Future<void> checkCurrentLocation() async {
    if (kIsWeb) return;
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 15),
      );

      final onSite = Geolocator.distanceBetween(COMPANY_LAT, COMPANY_LON, pos.latitude, pos.longitude) <= RADIUS_METERS;

      final prefs = await SharedPreferences.getInstance();
      final clockNo = prefs.getString('loggedInClockNo');
      if (clockNo == null) return;

      final emp = await _firestoreService.getEmployee(clockNo);
      if (emp != null && emp.isOnSite != onSite) {
        await _logGeoFenceEvent(
          eventType: onSite ? 'enter' : 'exit',
          source: 'resume_check',
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracy: pos.accuracy,
        );
        await _updateFirestore(onSite);
      }
    } catch (e) {
      debugPrint('checkCurrentLocation failed: $e');
    }
  }
}
