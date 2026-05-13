import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firestore_service.dart';
import 'notification_service.dart';

const String locationTaskName = "ctp_location_check_task";
const MethodChannel _channel = MethodChannel('ctp/geofence');

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      final prefs = await SharedPreferences.getInstance();
      final clockNo = prefs.getString('loggedInClockNo');
      if (clockNo == null) return Future.value(true);

      final settingsDoc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('geofence')
          .get();

      double lat = -29.994938052011612;
      double lng = 30.939421740548614;
      double radius = 800;

      if (settingsDoc.exists) {
        lat = settingsDoc.data()?['latitude']?.toDouble() ?? lat;
        lng = settingsDoc.data()?['longitude']?.toDouble() ?? lng;
        radius = settingsDoc.data()?['radius']?.toDouble() ?? radius;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 15),
      );

      final onSite =
          Geolocator.distanceBetween(lat, lng, pos.latitude, pos.longitude) <=
              radius;

      final firestore = FirestoreService();
      final emp = await firestore.getEmployee(clockNo);

      if (emp != null && emp.isOnSite != onSite) {
        await firestore.updateEmployee(emp.copyWith(isOnSite: onSite));
        await firestore.logGeoFenceEvent(
          clockNo: clockNo,
          eventType: onSite ? 'enter' : 'exit',
          source: 'workmanager_30min',
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracy: pos.accuracy,
        );
        debugPrint('📍 WorkManager 30-min check: isOnSite changed to $onSite');
      }
    } catch (e) {
      debugPrint('WorkManager error: $e');
    }
    return Future.value(true);
  });
}

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  String? _clockNo;
  final FirestoreService _firestoreService = FirestoreService();
  final NotificationService _notificationService = NotificationService();

  bool _isInitialized = false;

  Future<void> startNativeMonitoring(String clockNo) async {
    if (kIsWeb) return;
    if (_isInitialized) return;

    _clockNo = clockNo;
    await _requestPermissions();
    await _notificationService.initialize();

    try {
      final settingsDoc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('geofence')
          .get();

      double lat = -29.994938052011612;
      double lng = 30.939421740548614;
      double radius = 800.0;

      if (settingsDoc.exists) {
        lat = settingsDoc.data()?['latitude']?.toDouble() ?? lat;
        lng = settingsDoc.data()?['longitude']?.toDouble() ?? lng;
        radius = settingsDoc.data()?['radius']?.toDouble() ?? radius;
      }

      await _channel.invokeMethod('registerGeofence', {
        'clockNo': clockNo,
        'lat': lat,
        'lng': lng,
        'radius': radius,
      });

      debugPrint('✅ Native geofence registered');

      // Handle callbacks from the native GeofenceReceiver when the app is foregrounded.
      _channel.setMethodCallHandler(_handleNativeGeofenceEvent);

      await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
      await Workmanager().registerPeriodicTask(
        locationTaskName,
        locationTaskName,
        frequency: const Duration(minutes: 30),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
        ),
      );

      _isInitialized = true;
      debugPrint('✅ Hybrid geofence monitoring started (native + WorkManager 30-min)');
    } catch (e) {
      debugPrint('❌ Hybrid start failed: $e');
    }
  }

  Future<void> stopNativeMonitoring() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('stopGeofence');
    } catch (e) {
      debugPrint('stopGeofence error (non-fatal): $e');
    }
    await Workmanager().cancelByUniqueName(locationTaskName);
    _isInitialized = false;
    debugPrint('🛑 Hybrid monitoring stopped');
  }

  // Called by the native GeofenceReceiver via MethodChannel when the Flutter engine
  // is running (i.e., app is in foreground). Firestore is already updated on the
  // native side — this handler only drives the local notification and any UI refresh.
  Future<void> _handleNativeGeofenceEvent(MethodCall call) async {
    if (call.method != 'onGeofenceEvent') return;

    final isEntering = call.arguments['entering'] as bool;
    debugPrint('📍 Native geofence event received in Dart — entering=$isEntering');

    // Do NOT update Firestore here; GeofenceReceiver.kt already did it reliably.
    // Only trigger the local notification for user feedback.
    await _sendNotification(isEntering);
  }

  Future<void> checkCurrentLocation() async {
    try {
      debugPrint('📍 checkCurrentLocation() called');

      final settingsDoc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('geofence')
          .get();

      double lat = -29.994938052011612;
      double lng = 30.939421740548614;
      double radius = 500;

      if (settingsDoc.exists) {
        lat = settingsDoc.data()?['latitude']?.toDouble() ?? lat;
        lng = settingsDoc.data()?['longitude']?.toDouble() ?? lng;
        radius = settingsDoc.data()?['radius']?.toDouble() ?? radius;
        debugPrint('📍 Geofence settings → lat=$lat lng=$lng radius=$radius');
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 30),
      );

      final onSite =
          Geolocator.distanceBetween(lat, lng, pos.latitude, pos.longitude) <=
              radius;
      debugPrint('📍 Manual check → onSite=$onSite');

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
        debugPrint('📍 Manual check: status changed to $onSite');
      }
    } catch (e) {
      debugPrint('❌ Manual check failed: $e');
    }
  }

  Future<void> _sendNotification(bool onSite) async {
    final title = onSite ? '✅ On-Site Detected' : '📍 Left Site Area';
    final body = onSite
        ? 'You are within the company radius.'
        : 'You have left the site area.';
    await _notificationService.showOnSiteNotification(title: title, body: body);
  }

  Future<void> _requestPermissions() async {
    await ph.Permission.locationAlways.request();
    if (await ph.Permission.ignoreBatteryOptimizations.isDenied) {
      await ph.Permission.ignoreBatteryOptimizations.request();
    }
  }

  Future<void> logTestGeoFenceEvent(
      {required bool isEntering, String? notes}) async {
    final prefs = await SharedPreferences.getInstance();
    _clockNo ??= prefs.getString('loggedInClockNo');
    if (_clockNo == null) return;

    final emp = await _firestoreService.getEmployee(_clockNo!);
    if (emp != null) {
      await _firestoreService.updateEmployee(emp.copyWith(isOnSite: isEntering));
    }
    await _firestoreService.logGeoFenceEvent(
      clockNo: _clockNo!,
      eventType: isEntering ? 'enter' : 'exit',
      source: 'manual_test',
      notes: notes ?? 'Manual test from Diagnostics screen',
    );
    await _sendNotification(isEntering);
  }
}
