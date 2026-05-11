import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
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

  // ==================== START MONITORING ====================
  Future<void> startNativeMonitoring(String clockNo) async {
    if (kIsWeb) return;
    if (_isInitialized) return;

    _clockNo = clockNo;
    await _requestPermissions();
    await _notificationService.initialize();

    try {
      await _startBackgroundService();
      _isInitialized = true;
      debugPrint('✅ Location monitoring started (30 min interval when onsite)');
    } catch (e) {
      debugPrint('Location monitoring failed: $e');
    }
  }

  Future<void> stopNativeMonitoring() async {
    if (kIsWeb) return;
    FlutterBackgroundService().invoke("stopService");
    _isInitialized = false;
    debugPrint('🛑 Location monitoring stopped');
  }

  // ==================== BACKGROUND SERVICE ====================
  Future<void> _startBackgroundService() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onBackgroundServiceStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'location_channel',
        initialNotificationTitle: 'CTP Job Cards',
        initialNotificationContent: 'Monitoring location (every 30 min when onsite)',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: _onBackgroundServiceStart,
        onBackground: _onBackgroundServiceStart,
      ),
    );

    await service.startService();
  }

  @pragma('vm:entry-point')
  static Future<bool> _onBackgroundServiceStart(ServiceInstance service) async {
    Timer.periodic(const Duration(minutes: 30), (timer) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final clockNo = prefs.getString('loggedInClockNo');
        if (clockNo == null) return;

        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 15),
        );

        final onSite = Geolocator.distanceBetween(
          -29.994938052011612,
          30.939421740548614,
          pos.latitude,
          pos.longitude,
        ) <= 800;

        final firestore = FirestoreService();
        final emp = await firestore.getEmployee(clockNo);
        if (emp != null && emp.isOnSite != onSite) {
          await firestore.updateEmployee(emp.copyWith(isOnSite: onSite));

          await firestore.logGeoFenceEvent(
            clockNo: clockNo,
            eventType: onSite ? 'enter' : 'exit',
            source: 'background_check_30min',
            latitude: pos.latitude,
            longitude: pos.longitude,
            accuracy: pos.accuracy,
          );

          debugPrint('📍 30-min check: Status changed to ${onSite ? "ONSITE" : "OFFSITE"}');
        }
      } catch (e) {
        debugPrint('30-min background check error: $e');
      }
    });
    return true;
  }

  // ==================== MANUAL CHECK ====================
  Future<void> checkCurrentLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 15),
      );

      final onSite = Geolocator.distanceBetween(
        -29.994938052011612,
        30.939421740548614,
        pos.latitude,
        pos.longitude,
      ) <= 800;

      final prefs = await SharedPreferences.getInstance();
      final clockNo = prefs.getString('loggedInClockNo');
      if (clockNo == null) return;

      final emp = await _firestoreService.getEmployee(clockNo);
      if (emp != null && emp.isOnSite != onSite) {
        await _firestoreService.updateEmployee(emp.copyWith(isOnSite: onSite));

        await _firestoreService.logGeoFenceEvent(
          clockNo: clockNo,
          eventType: onSite ? 'enter' : 'exit',
          source: 'manual_check',
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracy: pos.accuracy,
        );

        debugPrint('📍 Manual check: Status changed to ${onSite ? "ONSITE" : "OFFSITE"}');
      }
    } catch (e) {
      debugPrint('Manual location check failed: $e');
    }
  }

  // ==================== TEST METHOD (Added Back) ====================
  Future<void> logTestGeoFenceEvent({required bool isEntering, String? notes}) async {
    final prefs = await SharedPreferences.getInstance();
    final clockNo = prefs.getString('loggedInClockNo') ?? 'UNKNOWN';

    await _firestoreService.logGeoFenceEvent(
      clockNo: clockNo,
      eventType: isEntering ? 'enter' : 'exit',
      source: 'manual_test',
      notes: notes ?? 'Manual test from Diagnostics screen',
    );
    await _updateFirestore(isEntering);
    await _sendNotification(isEntering);
  }

  // ==================== HELPERS ====================
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
    await ph.Permission.locationAlways.request();
  }
}