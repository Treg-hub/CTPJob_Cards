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

// ---------------------------------------------------------------------------
// WorkManager callback — runs in a separate isolate, no access to LocationService
// state. Only scheduled when employee is on-site. Self-cancels when off-site
// is detected so it stops running once the employee has left.
// ---------------------------------------------------------------------------
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      final prefs = await SharedPreferences.getInstance();
      final clockNo = prefs.getString('loggedInClockNo');

      // No logged-in user — cancel self, nothing to check.
      if (clockNo == null) {
        await Workmanager().cancelByUniqueName(locationTaskName);
        return Future.value(true);
      }

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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );

      final onSite =
          Geolocator.distanceBetween(lat, lng, pos.latitude, pos.longitude) <=
              radius;

      final firestore = FirestoreService();
      final emp = await firestore.getEmployee(clockNo);

      if (emp == null) return Future.value(true);

      if (emp.isOnSite != onSite) {
        // Status changed — update Firestore and log the transition.
        await firestore.updateEmployee(emp.copyWith(isOnSite: onSite));
        await firestore.logGeoFenceEvent(
          clockNo: clockNo,
          eventType: onSite ? 'enter' : 'exit',
          source: 'workmanager_30min',
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracy: pos.accuracy,
        );
        debugPrint('📍 WorkManager: isOnSite changed to $onSite');
      }

      // Employee is off-site (whether it just changed or was already off-site).
      // Cancel WorkManager — no point keeping the 30-min check running.
      if (!onSite) {
        await Workmanager().cancelByUniqueName(locationTaskName);
        debugPrint('🛑 WorkManager self-cancelled — employee is off-site');
      }
    } catch (e) {
      debugPrint('WorkManager error: $e');
    }
    return Future.value(true);
  });
}

// ---------------------------------------------------------------------------
// LocationService
// ---------------------------------------------------------------------------
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  String? _clockNo;
  final FirestoreService _firestoreService = FirestoreService();
  final NotificationService _notificationService = NotificationService();

  bool _isInitialized = false;

  // ---------------------------------------------------------------------------
  // Startup — called once after login. Registers the native geofence and sets
  // up the MethodChannel handler. WorkManager is NOT started here; it is
  // started by checkCurrentLocation() if the employee is already on-site, or
  // by _handleNativeGeofenceEvent() when an ENTER event fires.
  // ---------------------------------------------------------------------------
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

      // Handle ENTER/EXIT callbacks from GeofenceReceiver when app is foregrounded.
      _channel.setMethodCallHandler(_handleNativeGeofenceEvent);

      // Pre-initialize WorkManager so schedule/cancel calls work immediately.
      await Workmanager().initialize(callbackDispatcher);

      _isInitialized = true;
      debugPrint('✅ Native geofence monitoring started');
    } catch (e) {
      debugPrint('❌ Native monitoring start failed: $e');
    }
  }

  Future<void> stopNativeMonitoring() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('stopGeofence');
    } catch (e) {
      debugPrint('stopGeofence error (non-fatal): $e');
    }
    await _stopWorkManagerCheck();
    _isInitialized = false;
    debugPrint('🛑 Native monitoring stopped');
  }

  // ---------------------------------------------------------------------------
  // Native geofence callback (foreground only — app must be running).
  // Firestore is already updated by GeofenceReceiver.kt on both foreground and
  // background. This handler manages the local notification and WorkManager.
  // ---------------------------------------------------------------------------
  Future<void> _handleNativeGeofenceEvent(MethodCall call) async {
    if (call.method != 'onGeofenceEvent') return;

    final isEntering = call.arguments['entering'] as bool;
    debugPrint('📍 Native geofence event in Dart — entering=$isEntering');

    await _sendNotification(isEntering);

    if (isEntering) {
      // Employee arrived — start the 30-min on-site heartbeat check.
      await _startWorkManagerCheck();
    } else {
      // Employee left — stop the heartbeat, nothing to check until next ENTER.
      await _stopWorkManagerCheck();
    }
  }

  // ---------------------------------------------------------------------------
  // App-open location check — called each time the app comes to the foreground.
  // Compares the current GPS position against the Firestore isOnSite value and
  // corrects it if they disagree (catches missed geofence events).
  // Also syncs WorkManager: running only when on-site.
  // ---------------------------------------------------------------------------
  Future<void> checkCurrentLocation() async {
    try {
      debugPrint('📍 checkCurrentLocation() called');

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
        debugPrint('📍 Geofence settings → lat=$lat lng=$lng radius=$radius');
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 30),
        ),
      );

      final onSite =
          Geolocator.distanceBetween(lat, lng, pos.latitude, pos.longitude) <=
              radius;
      debugPrint('📍 App-open check → onSite=$onSite');

      final prefs = await SharedPreferences.getInstance();
      final clockNo = prefs.getString('loggedInClockNo');
      if (clockNo == null) return;

      final emp = await _firestoreService.getEmployee(clockNo);
      if (emp != null && emp.isOnSite != onSite) {
        // Firestore disagrees with GPS — a geofence event was missed. Correct it.
        await _firestoreService.updateEmployee(emp.copyWith(isOnSite: onSite));
        await _firestoreService.logGeoFenceEvent(
          clockNo: clockNo,
          eventType: onSite ? 'enter' : 'exit',
          source: 'app_open_check',
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracy: pos.accuracy,
        );
        debugPrint('📍 App-open check: corrected isOnSite to $onSite');
      }

      // Sync WorkManager with the actual on-site state regardless of whether
      // Firestore changed. If the app was restarted, WorkManager may need to be
      // re-scheduled (on-site) or confirmed-cancelled (off-site).
      if (onSite) {
        await _startWorkManagerCheck();
      } else {
        await _stopWorkManagerCheck();
      }
    } catch (e) {
      debugPrint('❌ checkCurrentLocation failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // WorkManager helpers
  // ---------------------------------------------------------------------------

  Future<void> _startWorkManagerCheck() async {
    try {
      await Workmanager().initialize(callbackDispatcher);
      await Workmanager().registerPeriodicTask(
        locationTaskName,
        locationTaskName,
        frequency: const Duration(minutes: 30),
        // KEEP: if already scheduled, leave it alone — don't reset the 30-min timer.
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
        ),
      );
      debugPrint('📍 WorkManager 30-min on-site check scheduled');
    } catch (e) {
      debugPrint('WorkManager start error (non-fatal): $e');
    }
  }

  Future<void> _stopWorkManagerCheck() async {
    try {
      await Workmanager().initialize(callbackDispatcher);
      await Workmanager().cancelByUniqueName(locationTaskName);
      debugPrint('🛑 WorkManager 30-min check stopped');
    } catch (e) {
      debugPrint('WorkManager stop error (non-fatal): $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  Future<void> _sendNotification(bool onSite) async {
    final title = onSite ? '✅ Arrived On-Site' : '📍 Left Site Area';
    final body = onSite
        ? 'You are now within the company radius.'
        : 'You have left the site area.';
    await _notificationService.showOnSiteNotification(title: title, body: body);
  }

  Future<void> _requestPermissions() async {
    // Android 10+ requires locationWhenInUse to be granted before locationAlways
    // can be requested. Skipping this step causes the system dialog to be
    // suppressed silently on many devices.
    final whenInUse = await ph.Permission.locationWhenInUse.status;
    if (!whenInUse.isGranted) {
      await ph.Permission.locationWhenInUse.request();
    }
    // Only request "always" after the foreground permission is in place.
    final always = await ph.Permission.locationAlways.status;
    if (!always.isGranted) {
      await ph.Permission.locationAlways.request();
    }
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
