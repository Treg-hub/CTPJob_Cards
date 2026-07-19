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
import '../constants/collections.dart';

const String locationTaskName = "ctp_location_check_task";
const MethodChannel _channel = MethodChannel('ctp/geofence');

/// Central geofence barrier (lat/lng/radius). Single source of truth: the
/// `settings/geofence` Firestore doc, edited via GeofenceEditorScreen.
class GeofenceConfig {
  final double latitude;
  final double longitude;
  final double radius;
  const GeofenceConfig(this.latitude, this.longitude, this.radius);
}

/// One default, used everywhere the `settings/geofence` doc is missing — keeps
/// the live geofence, the editor, the WorkManager check and the onboarding copy
/// in agreement instead of drifting apart.
const GeofenceConfig kDefaultGeofence =
    GeofenceConfig(-29.994938052011612, 30.939421740548614, 400.0);

/// Hysteresis margin (metres) for the off-site decision. Presence is sticky:
/// you become on-site within [GeofenceConfig.radius], but only flip back to
/// off-site once you are clearly beyond `radius + this margin`. The dead-band
/// between the two stops GPS jitter at the boundary from oscillating isOnSite
/// (the bug that spammed the on/off-site notice). Errs toward on-site, since a
/// false off-site is the harmful case — it parks notifications to the inbox and
/// blocks on-site-only job creation.
const double kGeofenceHysteresisMargin = 150.0;

/// Reads the central geofence barrier from `settings/geofence`, falling back to
/// [kDefaultGeofence]. Top-level so the WorkManager isolate can call it too.
Future<GeofenceConfig> loadGeofenceConfig() async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection(Collections.settings)
        .doc('geofence')
        .get();
    if (doc.exists) {
      final d = doc.data()!;
      return GeofenceConfig(
        (d['latitude'] as num?)?.toDouble() ?? kDefaultGeofence.latitude,
        (d['longitude'] as num?)?.toDouble() ?? kDefaultGeofence.longitude,
        (d['radius'] as num?)?.toDouble() ?? kDefaultGeofence.radius,
      );
    }
  } catch (e) {
    debugPrint('loadGeofenceConfig failed, using default: $e');
  }
  return kDefaultGeofence;
}

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

      final cfg = await loadGeofenceConfig();

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );

      final dist = Geolocator.distanceBetween(
          cfg.latitude, cfg.longitude, pos.latitude, pos.longitude);

      final firestore = FirestoreService();
      final emp = await firestore.getEmployee(clockNo);

      if (emp == null) return Future.value(true);

      // Hysteresis dead-band: once on-site, only flip off-site beyond
      // radius+margin; once off-site, only flip on-site within radius. Stops
      // boundary jitter from oscillating isOnSite.
      final onSite = emp.isOnSite
          ? dist <= cfg.radius + kGeofenceHysteresisMargin
          : dist <= cfg.radius;

      if (emp.isOnSite != onSite) {
        // Transition — the CF stamps the timestamps and logs the enter/exit to
        // app_geofence (source carries through).
        await firestore.updateMyPresence(isOnSite: onSite, source: 'workmanager_30min');
        debugPrint('📍 WorkManager: isOnSite changed to $onSite');
      } else if (onSite) {
        // No change but still on-site — heartbeat breadcrumb so the admin 14h
        // stuck-investigation has a trail ("log all adjustments incl. workmanager").
        await firestore.logGeoFenceEvent(
          clockNo: clockNo,
          eventType: 'check',
          source: 'workmanager_30min',
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracy: pos.accuracy,
          radiusUsed: cfg.radius,
        );
      }

      // Off-site (just changed or already) — cancel WorkManager. It must not
      // keep running once off-site; an ENTER restarts it.
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
      final cfg = await loadGeofenceConfig();

      await _channel.invokeMethod('registerGeofence', {
        'clockNo': clockNo,
        'lat': cfg.latitude,
        'lng': cfg.longitude,
        // Register at the outer (exit) band so the native EXIT only fires once
        // clearly off-site — hysteresis against boundary jitter while the app is
        // backgrounded/killed. The precise on-site radius is enforced by the
        // polling checks (app-open + 30-min WorkManager).
        'radius': cfg.radius + kGeofenceHysteresisMargin,
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

    // Foreground fallback: GeofenceReceiver.kt writes presence itself, but if
    // that direct write is ever denied/failed, correct it through the CF. The CF
    // is transition-aware, so this is a no-op when the native write already
    // landed (and therefore logs nothing in the normal case).
    await _firestoreService.updateMyPresence(
        isOnSite: isEntering, source: 'native_geofence_fg');

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
  /// Returns the resolved on-site state after the GPS check, or null when the
  /// check could not run (web, no clock number, GPS error).
  Future<bool?> checkCurrentLocation() async {
    // The web build has no geofence and never writes presence — mobile is the
    // sole source of truth. Guard so the web build doesn't prompt for location.
    if (kIsWeb) return null;
    try {
      debugPrint('📍 checkCurrentLocation() called');

      final cfg = await loadGeofenceConfig();

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 30),
        ),
      );

      final dist = Geolocator.distanceBetween(
          cfg.latitude, cfg.longitude, pos.latitude, pos.longitude);

      final prefs = await SharedPreferences.getInstance();
      final clockNo = prefs.getString('loggedInClockNo');
      if (clockNo == null) return null;

      final emp = await _firestoreService.getEmployee(clockNo);
      if (emp == null) return null;

      // Hysteresis dead-band (see callbackDispatcher) — sticky presence so a
      // single jittery fix near the boundary can't flip isOnSite.
      final onSite = emp.isOnSite
          ? dist <= cfg.radius + kGeofenceHysteresisMargin
          : dist <= cfg.radius;
      debugPrint('📍 App-open check → dist=${dist.toStringAsFixed(0)} onSite=$onSite');

      if (emp.isOnSite != onSite) {
        // Firestore disagrees with GPS — a geofence event was missed. Correct it
        // via the CF (which stamps timestamps + logs the enter/exit).
        await _firestoreService.updateMyPresence(
            isOnSite: onSite, source: 'app_open_check');
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
      return onSite;
    } catch (e) {
      debugPrint('❌ checkCurrentLocation failed: $e');
      return null;
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
      await _firestoreService.updateMyPresence(
          isOnSite: isEntering, source: 'manual_test');
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
