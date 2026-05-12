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
        desiredAccuracy: LocationAccuracy.low, // Battery optimization
        timeLimit: const Duration(seconds: 10),
      );

      final onSite = Geolocator.distanceBetween(lat, lng, pos.latitude, pos.longitude) <= radius;

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

        debugPrint('📍 WorkManager 30-min check: Status changed to $onSite');
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
      debugPrint('📍 Loading geofence from Firebase...');

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
        debugPrint('📍 Using Firebase geofence: lat=$lat, lng=$lng, radius=$radius');
      } else {
        debugPrint('📍 Using default geofence values');
      }

      // Register native geofence (Android)
      await _channel.invokeMethod('registerGeofence', {
        'clockNo': clockNo,
        'lat': lat,
        'lng': lng,
        'radius': radius,
      });

      debugPrint('✅ Native geofence registered successfully');

      _channel.setMethodCallHandler(_handleMethodCall);

      await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

      await Workmanager().registerPeriodicTask(
        locationTaskName,
        locationTaskName,
        frequency: const Duration(minutes: 30),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false, // More reliable
        ),
      );

      _isInitialized = true;
      debugPrint('✅ Hybrid geofence monitoring started successfully');
    } catch (e) {
      debugPrint('❌ Native registration failed, falling back to Workmanager only: $e');
      // Still start Workmanager as fallback
      await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
      await Workmanager().registerPeriodicTask(
        locationTaskName,
        locationTaskName,
        frequency: const Duration(minutes: 30),
      );
    }
  }

  Future<void> stopNativeMonitoring() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('stopGeofence');
    } catch (_) {}
    await Workmanager().cancelByUniqueName(locationTaskName);
    _isInitialized = false;
    debugPrint('🛑 Hybrid monitoring stopped');
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    debugPrint('📍 _handleMethodCall received: ${call.method}');

    if (call.method == 'onGeofenceEvent') {
      debugPrint('✅ Native onGeofenceEvent received!');
      final isEntering = call.arguments['entering'] as bool;
      final eventType = isEntering ? 'enter' : 'exit';

      await _logGeoFenceEvent(eventType: eventType, source: 'native_geofence');
      await _updateFirestore(isEntering);
      await _sendNotification(isEntering);
    }
  }

  Future<void> checkCurrentLocation() async {
    try {
      debugPrint('📍 Manual location check called');

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
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 10),
      );

      final onSite = Geolocator.distanceBetween(lat, lng, pos.latitude, pos.longitude) <= radius;
      debugPrint('📍 Current location check → OnSite: $onSite');

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
      }
    } catch (e) {
      debugPrint('❌ Manual check failed: $e');
    }
  }

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
    // Request battery optimization exemption (important for reliability)
    if (await ph.Permission.ignoreBatteryOptimizations.isDenied) {
      await ph.Permission.ignoreBatteryOptimizations.request();
    }
  }

  Future<void> logTestGeoFenceEvent({required bool isEntering, String? notes}) async {
    await _logGeoFenceEvent(
      eventType: isEntering ? 'enter' : 'exit',
      source: 'manual_test',
      notes: notes ?? 'Manual test from Diagnostics screen',
    );
    await _updateFirestore(isEntering);
    await _sendNotification(isEntering);
  }
}
