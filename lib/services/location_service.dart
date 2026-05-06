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

  // ==================== START / STOP ====================
  Future<void> startNativeMonitoring(String clockNo) async {
    if (kIsWeb) {
      debugPrint('📍 Geofencing not supported on web');
      return;
    }

    _clockNo = clockNo;
    await _requestPermissions();
    await _notificationService.initialize();

    try {
      // Use the new improved method
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
    debugPrint('Geofence stopped');
  }

  // ==================== 30-MINUTE ON-SITE TIMER ====================
  void _startOnSiteRecheckTimer() {
    _stopOnSiteRecheckTimer();

    _onSiteRecheckTimer = Timer.periodic(const Duration(minutes: 30), (timer) async {
      await backgroundCheck();
    });

    debugPrint('✅ 30-minute on-site recheck timer started');
  }

  void _stopOnSiteRecheckTimer() {
    _onSiteRecheckTimer?.cancel();
    _onSiteRecheckTimer = null;
  }

  // ==================== HANDLE GEOFENCE EVENTS FROM NATIVE ====================
  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onGeofenceEvent') {
      final isEntering = call.arguments['entering'] as bool;

      await _updateFirestore(isEntering);
      await _sendNotification(isEntering);

      if (isEntering) {
        _startOnSiteRecheckTimer();
      } else {
        _stopOnSiteRecheckTimer();
      }
    }
  }

  // ==================== HELPER METHODS ====================
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

  Future<void> _checkFallback() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        final onSite = Geolocator.distanceBetween(COMPANY_LAT, COMPANY_LON, pos.latitude, pos.longitude) <= RADIUS_METERS;
        await _updateFirestore(onSite);
        await _sendNotification(onSite);
      }
    } catch (e) {
      debugPrint('Fallback check failed: $e');
    }
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

  // ==================== 30-MIN BACKGROUND CHECK ====================
  Future<void> backgroundCheck() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clockNo = prefs.getString('loggedInClockNo');
      if (clockNo == null) return;

      final emp = await _firestoreService.getEmployee(clockNo);
      if (emp == null || !emp.isOnSite) return;

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 15),
      );

      final onSite = Geolocator.distanceBetween(COMPANY_LAT, COMPANY_LON, pos.latitude, pos.longitude) <= RADIUS_METERS;

      if (!onSite) {
        await _updateFirestore(false);
        await _sendNotification(false);
        _stopOnSiteRecheckTimer();
      }
    } catch (e) {
      debugPrint('backgroundCheck failed: $e');
    }
  }
  
  // ==================== CHECK CURRENT LOCATION (for app resume) ====================
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
        await _updateFirestore(onSite);
      }
    } catch (e) {
      debugPrint('checkCurrentLocation failed: $e');
    }
  }
}