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

  // ==================== START / STOP ====================\n  Future<void> startNativeMonitoring(String clockNo) async {
    if (kIsWeb) {
      debugPrint('📍 Geofencing not supported on web');
      return;
    }

    _clockNo = clockNo;
    debugPrint('📍 [LocationService] Starting native monitoring for clockNo: $clockNo');
    await _requestPermissions();
    await _notificationService.initialize();

    try {
      await _channel.invokeMethod('registerGeofence', {
        'clockNo': clockNo,
        'lat': COMPANY_LAT,
        'lng': COMPANY_LON,
        'radius': RADIUS_METERS,
      });

      debugPrint('✅ [LocationService] Geofence registered successfully for $clockNo');
    } catch (e) {
      debugPrint('❌ [LocationService] Geofence registration FAILED: $e');
    }

    await _checkFallback();
  }

  Future<void> stopNativeMonitoring() async {
    if (kIsWeb) return;

    await _channel.invokeMethod('stopGeofence');
    _stopOnSiteRecheckTimer();
    debugPrint('📍 [LocationService] Geofence stopped');
  }

  // ==================== 30-MINUTE ON-SITE TIMER ====================\n  void _startOnSiteRecheckTimer() {
    _stopOnSiteRecheckTimer();

    _onSiteRecheckTimer = Timer.periodic(const Duration(minutes: 30), (timer) async {
      debugPrint('📍 [LocationService] Running 30-min background recheck...');
      await backgroundCheck();
    });

    debugPrint('✅ [LocationService] 30-minute on-site recheck timer started');
  }

  void _stopOnSiteRecheckTimer() {
    _onSiteRecheckTimer?.cancel();
    _onSiteRecheckTimer = null;
  }

  // ==================== HANDLE GEOFENCE EVENTS FROM NATIVE ====================\n  Future<void> _handleMethodCall(MethodCall call) async {
    debugPrint('📍 [LocationService] Received native method call: ${call.method}');

    if (call.method == 'onGeofenceEvent') {
      final isEntering = call.arguments['entering'] as bool;
      debugPrint('📍 [LocationService] Geofence event received → entering: $isEntering');

      await _updateFirestore(isEntering);
      await _sendNotification(isEntering);

      if (isEntering) {
        _startOnSiteRecheckTimer();
      } else {
        _stopOnSiteRecheckTimer();
      }
    }
  }

  // ==================== HELPER METHODS ====================\n  Future<void> _requestPermissions() async {
    debugPrint('📍 [LocationService] Requesting location permissions...');
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('❌ [LocationService] Location services are DISABLED');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      debugPrint('❌ [LocationService] Location permission DENIED FOREVER');
      return;
    }

    await ph.Permission.locationAlways.request();
    debugPrint('✅ [LocationService] Location permissions granted');
  }

  Future<void> _checkFallback() async {
    debugPrint('📍 [LocationService] Running fallback GPS check...');
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        final onSite = Geolocator.distanceBetween(COMPANY_LAT, COMPANY_LON, pos.latitude, pos.longitude) <= RADIUS_METERS;
        debugPrint('📍 [LocationService] Fallback check → onSite: $onSite (lat: ${pos.latitude}, lon: ${pos.longitude})');
        await _updateFirestore(onSite);
        await _sendNotification(onSite);
      } else {
        debugPrint('⚠️ [LocationService] No last known position available for fallback check');
      }
    } catch (e) {
      debugPrint('❌ [LocationService] Fallback check FAILED: $e');
    }
  }

  Future<void> _updateFirestore(bool onSite) async {
    debugPrint('📍 [LocationService] Attempting to update Firestore → clockNo: $_clockNo, onSite: $onSite');

    if (_clockNo == null) {
      debugPrint('❌ [LocationService] Cannot update Firestore — _clockNo is NULL');
      return;
    }

    try {
      final emp = await _firestoreService.getEmployee(_clockNo!);
      if (emp != null) {
        await _firestoreService.updateEmployee(emp.copyWith(isOnSite: onSite));
        debugPrint('✅ [LocationService] SUCCESS: isOnSite updated to $onSite for ${_clockNo}');
      } else {
        debugPrint('❌ [LocationService] Employee not found in Firestore for clockNo: ${_clockNo}');
      }
    } catch (e) {
      debugPrint('❌ [LocationService] Firestore update FAILED: $e');
    }
  }

  Future<void> _sendNotification(bool onSite) async {
    final title = onSite ? '✅ On-Site Detected' : '📍 Left Site Area';
    final body = onSite ? 'You are within the company radius.' : 'You have left the site area.';
    await _notificationService.showOnSiteNotification(title: title, body: body);
    debugPrint('📍 [LocationService] Notification sent: $title');
  }

  // ==================== 30-MIN BACKGROUND CHECK ====================\n  Future<void> backgroundCheck() async {
    debugPrint('📍 [LocationService] backgroundCheck() started');
    try {
      final prefs = await SharedPreferences.getInstance();
      final clockNo = prefs.getString('loggedInClockNo');
      if (clockNo == null) {
        debugPrint('❌ [LocationService] backgroundCheck skipped — no loggedInClockNo in prefs');
        return;
      }

      final emp = await _firestoreService.getEmployee(clockNo);
      if (emp == null || !emp.isOnSite) {
        debugPrint('📍 [LocationService] backgroundCheck skipped — employee not on site or not found');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 15),
      );

      final onSite = Geolocator.distanceBetween(COMPANY_LAT, COMPANY_LON, pos.latitude, pos.longitude) <= RADIUS_METERS;
      debugPrint('📍 [LocationService] backgroundCheck result → onSite: $onSite');

      if (!onSite) {
        await _updateFirestore(false);
        await _sendNotification(false);
        _stopOnSiteRecheckTimer();
      }
    } catch (e) {
      debugPrint('❌ [LocationService] backgroundCheck FAILED: $e');
    }
  }
  
  // ==================== CHECK CURRENT LOCATION (for app resume) ====================\n  Future<void> checkCurrentLocation() async {
    if (kIsWeb) return;
    debugPrint('📍 [LocationService] checkCurrentLocation() called (app resume)');

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        debugPrint('❌ [LocationService] checkCurrentLocation skipped — no location permission');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 15),
      );

      final onSite = Geolocator.distanceBetween(COMPANY_LAT, COMPANY_LON, pos.latitude, pos.longitude) <= RADIUS_METERS;
      debugPrint('📍 [LocationService] checkCurrentLocation GPS result → onSite: $onSite');

      final prefs = await SharedPreferences.getInstance();
      final clockNo = prefs.getString('loggedInClockNo');
      if (clockNo == null) {
        debugPrint('❌ [LocationService] checkCurrentLocation skipped — no clockNo in prefs');
        return;
      }

      final emp = await _firestoreService.getEmployee(clockNo);
      if (emp != null && emp.isOnSite != onSite) {
        debugPrint('📍 [LocationService] Status changed — updating Firestore...');
        await _updateFirestore(onSite);
      } else {
        debugPrint('📍 [LocationService] No status change needed (current: ${emp?.isOnSite}, new: $onSite)');
      }
    } catch (e) {
      debugPrint('❌ [LocationService] checkCurrentLocation FAILED: $e');
    }
  }
}