// location_service.dart
// Native geofence + WorkManager presence. Quiet at home (strict enter);
// sticky on-site in factory dead zones (no GPS/signal ≠ left site).

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../constants/collections.dart';
import 'firestore_service.dart';
import 'notification_service.dart';

/// On-site heartbeat (while marked on-site).
const String locationTaskName = 'ctp_location_check_task';

/// Off-site reconcile — GPS promote only with a clear in-radius fix.
const String offsiteReconcileTaskName = 'ctp_offsite_reconcile_task';

/// Early post-enter one-shot heartbeats (unique name prefix).
const String onsiteBoostTaskPrefix = 'ctp_onsite_boost_';

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
/// off-site once you are clearly beyond `radius + this margin`.
const double kGeofenceHysteresisMargin = 150.0;

/// Reject GPS for any status decision above this (factory dead zones / indoor
/// multipath). Prefer "no change" over a wrong flip.
const double kMaxUsableAccuracyM = 400.0;

/// Promote off→on only with a tighter accuracy (home-quiet guarantee).
const double kMaxAccuracyForEnterM = 150.0;

/// Demote on→off only when accuracy is good enough to trust "outside".
const double kMaxAccuracyForExitM = 250.0;

/// Still log a heartbeat breadcrumb up to this accuracy while on-site.
const double kMaxAccuracyForCheckProofM = 350.0;

const String _prefsLastKnownOnSite = 'presence_lastKnownIsOnSite';
const String _prefsPending = 'presence_pending_v1';

/// Pure decision helper — unit-testable.
///
/// Returns:
/// - `true` / `false` when GPS is good enough to decide
/// - `null` when the fix is unusable (dead zone / timeout path should pass null)
///   so the caller **must not** change isOnSite (sticky).
bool? resolveOnSiteFromFix({
  required bool currentlyOnSite,
  required double distM,
  required double radiusM,
  required double accuracyM,
  double hysteresisM = kGeofenceHysteresisMargin,
  double maxUsableAccuracyM = kMaxUsableAccuracyM,
  double maxEnterAccuracyM = kMaxAccuracyForEnterM,
  double maxExitAccuracyM = kMaxAccuracyForExitM,
}) {
  if (accuracyM <= 0 || accuracyM > maxUsableAccuracyM) return null;

  if (currentlyOnSite) {
    // Sticky on-site: only leave with a clear outside fix.
    if (accuracyM > maxExitAccuracyM) return null;
    if (distM > radiusM + hysteresisM) return false;
    return true;
  }

  // Off-site → on-site only inside the real radius with good accuracy.
  if (accuracyM > maxEnterAccuracyM) return null;
  if (distM <= radiusM) return true;
  return false;
}

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
// WorkManager callback — separate isolate. Handles:
//   • on-site periodic heartbeat
//   • post-enter boost one-shots
//   • off-site reconcile (strict enter only)
// Dead zone: GPS failure / bad accuracy → no presence flip; retry later.
// No-signal: queue writes; do not require network to *run* the task.
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
      if (clockNo == null) {
        await Workmanager().cancelByUniqueName(locationTaskName);
        await Workmanager().cancelByUniqueName(offsiteReconcileTaskName);
        return true;
      }

      // Flush anything queued while in a no-signal pocket of the plant.
      await _flushPendingPresence(prefs);

      final isBoost = task.startsWith(onsiteBoostTaskPrefix);
      final isReconcile = task == offsiteReconcileTaskName;

      final source = isReconcile
          ? 'offsite_reconcile'
          : (isBoost ? 'workmanager_boost' : 'workmanager_30min');

      final cfg = await loadGeofenceConfig();

      Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 20),
          ),
        );
      } catch (e) {
        // Dead zone / no GPS: leave presence unchanged (sticky).
        debugPrint('WorkManager GPS failed (no flip): $e');
        return true;
      }

      final dist = Geolocator.distanceBetween(
        cfg.latitude,
        cfg.longitude,
        pos.latitude,
        pos.longitude,
      );

      final firestore = FirestoreService();
      final emp = await firestore.getEmployee(clockNo);
      final currentlyOnSite = emp?.isOnSite ??
          prefs.getBool(_prefsLastKnownOnSite) ??
          false;

      final decided = resolveOnSiteFromFix(
        currentlyOnSite: currentlyOnSite,
        distM: dist,
        radiusM: cfg.radius,
        accuracyM: pos.accuracy,
      );

      if (decided == null) {
        // Unusable fix — factory indoor / multipath. Do not demote or promote.
        debugPrint(
          'WorkManager: unusable fix acc=${pos.accuracy.toStringAsFixed(0)}m '
          'dist=${dist.toStringAsFixed(0)}m — sticky (no flip)',
        );
        return true;
      }

      if (currentlyOnSite != decided) {
        final ok = await _writePresenceOrQueue(
          prefs: prefs,
          firestore: firestore,
          isOnSite: decided,
          source: source,
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracy: pos.accuracy,
          radiusUsed: cfg.radius,
          eventType: decided ? 'enter' : 'exit',
        );
        debugPrint(
          '📍 WorkManager ($source): isOnSite $currentlyOnSite → $decided '
          '(queued=${!ok})',
        );
      } else if (decided && pos.accuracy <= kMaxAccuracyForCheckProofM) {
        // Heartbeat proof for stale-presence CF (only while on-site).
        await _writeCheckOrQueue(
          prefs: prefs,
          firestore: firestore,
          clockNo: clockNo,
          source: source,
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracy: pos.accuracy,
          radiusUsed: cfg.radius,
        );
      }

      await prefs.setBool(_prefsLastKnownOnSite, decided);

      // Keep schedules aligned with resolved state.
      if (decided) {
        await _wmStartOnsiteHeartbeat(rescheduleBoost: false);
        await Workmanager().cancelByUniqueName(offsiteReconcileTaskName);
      } else {
        await Workmanager().cancelByUniqueName(locationTaskName);
        await _wmCancelBoosts();
        await _wmStartOffsiteReconcile();
      }
    } catch (e) {
      debugPrint('WorkManager error: $e');
    }
    return true;
  });
}

// ---- isolate helpers (top-level; no LocationService instance) --------------

Future<bool> _writePresenceOrQueue({
  required SharedPreferences prefs,
  required FirestoreService firestore,
  required bool isOnSite,
  required String source,
  double? latitude,
  double? longitude,
  double? accuracy,
  double? radiusUsed,
  required String eventType,
}) async {
  final ok =
      await firestore.updateMyPresence(isOnSite: isOnSite, source: source);
  if (ok) {
    await prefs.setBool(_prefsLastKnownOnSite, isOnSite);
    await prefs.remove(_prefsPending);
    return true;
  }
  debugPrint('Presence write failed — queueing for signal return');
  await prefs.setString(
    _prefsPending,
    jsonEncode({
      'kind': 'presence',
      'isOnSite': isOnSite,
      'source': source,
      'eventType': eventType,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'radiusUsed': radiusUsed,
      'queuedAtMs': DateTime.now().millisecondsSinceEpoch,
    }),
  );
  // Local sticky so resume UI / next reconcile know intent while offline.
  await prefs.setBool(_prefsLastKnownOnSite, isOnSite);
  return false;
}

Future<void> _writeCheckOrQueue({
  required SharedPreferences prefs,
  required FirestoreService firestore,
  required String clockNo,
  required String source,
  required double latitude,
  required double longitude,
  required double accuracy,
  required double radiusUsed,
}) async {
  final ok = await firestore.logGeoFenceEvent(
    clockNo: clockNo,
    eventType: 'check',
    source: source,
    latitude: latitude,
    longitude: longitude,
    accuracy: accuracy,
    radiusUsed: radiusUsed,
  );
  if (ok) return;

  debugPrint('Check log failed — queueing for signal return');
  final existing = prefs.getString(_prefsPending);
  // Do not overwrite a pending enter/exit with a check.
  if (existing != null) {
    try {
      final m = jsonDecode(existing) as Map<String, dynamic>;
      if (m['kind'] == 'presence') return;
    } catch (_) {}
  }
  await prefs.setString(
    _prefsPending,
    jsonEncode({
      'kind': 'check',
      'clockNo': clockNo,
      'source': source,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'radiusUsed': radiusUsed,
      'queuedAtMs': DateTime.now().millisecondsSinceEpoch,
    }),
  );
}

Future<void> _flushPendingPresence(SharedPreferences prefs) async {
  final raw = prefs.getString(_prefsPending);
  if (raw == null) return;
  try {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final firestore = FirestoreService();
    final kind = m['kind'] as String? ?? 'presence';
    if (kind == 'presence') {
      final isOnSite = m['isOnSite'] as bool? ?? false;
      final source = '${m['source'] ?? 'queued'}_flush';
      await firestore.updateMyPresence(isOnSite: isOnSite, source: source);
      await prefs.setBool(_prefsLastKnownOnSite, isOnSite);
    } else if (kind == 'check') {
      final clockNo = m['clockNo'] as String? ?? prefs.getString('loggedInClockNo');
      if (clockNo != null) {
        await firestore.logGeoFenceEvent(
          clockNo: clockNo,
          eventType: 'check',
          source: '${m['source'] ?? 'queued'}_flush',
          latitude: (m['latitude'] as num?)?.toDouble(),
          longitude: (m['longitude'] as num?)?.toDouble(),
          accuracy: (m['accuracy'] as num?)?.toDouble(),
          radiusUsed: (m['radiusUsed'] as num?)?.toDouble(),
          notes: 'Flushed after no-signal pocket',
        );
      }
    }
    await prefs.remove(_prefsPending);
    debugPrint('📍 Flushed pending presence/check');
  } catch (e) {
    debugPrint('Flush pending presence failed (will retry): $e');
  }
}

Future<void> _wmStartOnsiteHeartbeat({required bool rescheduleBoost}) async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    locationTaskName,
    locationTaskName,
    frequency: const Duration(minutes: 20),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    // Run even without data (factory dead zones) — writes queue if offline.
    constraints: Constraints(
      networkType: NetworkType.notRequired,
      requiresBatteryNotLow: false,
    ),
  );
  if (rescheduleBoost) {
    await _wmScheduleBoosts();
  }
}

Future<void> _wmScheduleBoosts() async {
  // Early checks after enter so the 2h stale CF does not win before the first
  // periodic tick (OEM often delays the first 20–30 min job).
  const delays = [10, 25, 45];
  for (final minutes in delays) {
    final name = '$onsiteBoostTaskPrefix$minutes';
    try {
      await Workmanager().registerOneOffTask(
        name,
        name,
        initialDelay: Duration(minutes: minutes),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        constraints: Constraints(
          networkType: NetworkType.notRequired,
          requiresBatteryNotLow: false,
        ),
      );
    } catch (e) {
      debugPrint('Boost schedule $minutes failed: $e');
    }
  }
}

Future<void> _wmCancelBoosts() async {
  for (final minutes in [10, 25, 45]) {
    try {
      await Workmanager().cancelByUniqueName('$onsiteBoostTaskPrefix$minutes');
    } catch (_) {}
  }
}

Future<void> _wmStartOffsiteReconcile() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    offsiteReconcileTaskName,
    offsiteReconcileTaskName,
    // ~hourly is enough for continental recovery without heavy battery use.
    // Android may batch; still far better than "only on app open".
    frequency: const Duration(minutes: 60),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(
      networkType: NetworkType.notRequired,
      requiresBatteryNotLow: false,
    ),
  );
  debugPrint('📍 Off-site reconcile scheduled');
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

  /// Registers native geofence + WorkManager. Safe to call again after
  /// permission fix / resume ([force] re-registers the fence).
  Future<void> startNativeMonitoring(
    String clockNo, {
    bool force = false,
  }) async {
    if (kIsWeb) return;

    _clockNo = clockNo;
    await _requestPermissions();
    await _notificationService.initialize();

    try {
      await Workmanager().initialize(callbackDispatcher);
      await _registerNativeFence(clockNo);
      _channel.setMethodCallHandler(_handleNativeGeofenceEvent);

      // Flush any presence writes that failed in a no-signal pocket.
      final prefs = await SharedPreferences.getInstance();
      await _flushPendingPresence(prefs);

      if (!_isInitialized || force) {
        _isInitialized = true;
        debugPrint('✅ Native geofence monitoring started (force=$force)');
      }
    } catch (e) {
      debugPrint('❌ Native monitoring start failed: $e');
    }
  }

  Future<void> _registerNativeFence(String clockNo) async {
    final cfg = await loadGeofenceConfig();
    await _channel.invokeMethod('registerGeofence', {
      'clockNo': clockNo,
      'lat': cfg.latitude,
      'lng': cfg.longitude,
      // Outer band for native EXIT hysteresis; enter/stay precision is enforced
      // by polling (app-open + WorkManager) using the real radius.
      'radius': cfg.radius + kGeofenceHysteresisMargin,
    });
    debugPrint('✅ Native geofence registered');
  }

  Future<void> stopNativeMonitoring() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('stopGeofence');
    } catch (e) {
      debugPrint('stopGeofence error (non-fatal): $e');
    }
    await _stopAllBackgroundLocation();
    _isInitialized = false;
    debugPrint('🛑 Native monitoring stopped');
  }

  Future<void> _handleNativeGeofenceEvent(MethodCall call) async {
    if (call.method != 'onGeofenceEvent') return;

    final isEntering = call.arguments['entering'] as bool;
    debugPrint('📍 Native geofence event in Dart — entering=$isEntering');

    await _sendNotification(isEntering);

    final prefs = await SharedPreferences.getInstance();
    await _writePresenceOrQueue(
      prefs: prefs,
      firestore: _firestoreService,
      isOnSite: isEntering,
      source: 'native_geofence_fg',
      eventType: isEntering ? 'enter' : 'exit',
    );
    await prefs.setBool(_prefsLastKnownOnSite, isEntering);

    if (isEntering) {
      await _startOnsiteMonitoring(boost: true);
    } else {
      await _startOffsiteReconcileOnly();
    }
  }

  /// App-open / resume GPS check. Returns resolved on-site state, or **null**
  /// when GPS fails (dead zone) so UI must not force a flip.
  Future<bool?> checkCurrentLocation() async {
    if (kIsWeb) return null;
    try {
      debugPrint('📍 checkCurrentLocation() called');

      final prefs = await SharedPreferences.getInstance();
      await _flushPendingPresence(prefs);

      final clockNo = prefs.getString('loggedInClockNo') ?? _clockNo;
      if (clockNo == null) return null;

      // Ensure fence is registered whenever we have Always location.
      final always = await ph.Permission.locationAlways.status;
      if (always.isGranted) {
        await startNativeMonitoring(clockNo, force: true);
      }

      final cfg = await loadGeofenceConfig();

      Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 30),
          ),
        );
      } catch (e) {
        // Dead zone: do not change isOnSite; keep existing schedules.
        debugPrint('❌ checkCurrentLocation GPS failed (sticky): $e');
        return null;
      }

      final dist = Geolocator.distanceBetween(
        cfg.latitude,
        cfg.longitude,
        pos.latitude,
        pos.longitude,
      );

      final emp = await _firestoreService.getEmployee(clockNo);
      final currentlyOnSite = emp?.isOnSite ??
          prefs.getBool(_prefsLastKnownOnSite) ??
          false;

      final decided = resolveOnSiteFromFix(
        currentlyOnSite: currentlyOnSite,
        distM: dist,
        radiusM: cfg.radius,
        accuracyM: pos.accuracy,
      );

      debugPrint(
        '📍 App-open check → dist=${dist.toStringAsFixed(0)} '
        'acc=${pos.accuracy.toStringAsFixed(0)} decided=$decided '
        '(was $currentlyOnSite)',
      );

      if (decided == null) {
        // Unusable fix — leave presence and schedules alone.
        return currentlyOnSite;
      }

      if (currentlyOnSite != decided) {
        await _writePresenceOrQueue(
          prefs: prefs,
          firestore: _firestoreService,
          isOnSite: decided,
          source: 'app_open_check',
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracy: pos.accuracy,
          radiusUsed: cfg.radius,
          eventType: decided ? 'enter' : 'exit',
        );
        debugPrint('📍 App-open check: corrected isOnSite to $decided');
      } else if (decided && pos.accuracy <= kMaxAccuracyForCheckProofM) {
        // Breadcrumb while already on-site (helps 2h stale window).
        await _writeCheckOrQueue(
          prefs: prefs,
          firestore: _firestoreService,
          clockNo: clockNo,
          source: 'app_open_check',
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracy: pos.accuracy,
          radiusUsed: cfg.radius,
        );
      }

      await prefs.setBool(_prefsLastKnownOnSite, decided);

      if (decided) {
        await _startOnsiteMonitoring(boost: currentlyOnSite != decided);
      } else {
        await _startOffsiteReconcileOnly();
      }
      return decided;
    } catch (e) {
      debugPrint('❌ checkCurrentLocation failed: $e');
      return null;
    }
  }

  Future<void> _startOnsiteMonitoring({required bool boost}) async {
    try {
      await _wmStartOnsiteHeartbeat(rescheduleBoost: boost);
      await Workmanager().cancelByUniqueName(offsiteReconcileTaskName);
      debugPrint('📍 On-site heartbeat active (boost=$boost)');
    } catch (e) {
      debugPrint('On-site WorkManager error (non-fatal): $e');
    }
  }

  Future<void> _startOffsiteReconcileOnly() async {
    try {
      await Workmanager().initialize(callbackDispatcher);
      await Workmanager().cancelByUniqueName(locationTaskName);
      await _wmCancelBoosts();
      await _wmStartOffsiteReconcile();
    } catch (e) {
      debugPrint('Off-site reconcile schedule error (non-fatal): $e');
    }
  }

  Future<void> _stopAllBackgroundLocation() async {
    try {
      await Workmanager().initialize(callbackDispatcher);
      await Workmanager().cancelByUniqueName(locationTaskName);
      await Workmanager().cancelByUniqueName(offsiteReconcileTaskName);
      await _wmCancelBoosts();
    } catch (e) {
      debugPrint('Stop background location error (non-fatal): $e');
    }
  }

  Future<void> _sendNotification(bool onSite) async {
    final title = onSite ? '✅ Arrived On-Site' : '📍 Left Site Area';
    final body = onSite
        ? 'You are now within the company radius.'
        : 'You have left the site area.';
    await _notificationService.showOnSiteNotification(title: title, body: body);
  }

  Future<void> _requestPermissions() async {
    final whenInUse = await ph.Permission.locationWhenInUse.status;
    if (!whenInUse.isGranted) {
      await ph.Permission.locationWhenInUse.request();
    }
    final always = await ph.Permission.locationAlways.status;
    if (!always.isGranted) {
      await ph.Permission.locationAlways.request();
    }
    if (await ph.Permission.ignoreBatteryOptimizations.isDenied) {
      await ph.Permission.ignoreBatteryOptimizations.request();
    }
  }

  Future<void> logTestGeoFenceEvent({
    required bool isEntering,
    String? notes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _clockNo ??= prefs.getString('loggedInClockNo');
    if (_clockNo == null) return;

    final emp = await _firestoreService.getEmployee(_clockNo!);
    if (emp != null) {
      await _firestoreService.updateMyPresence(
        isOnSite: isEntering,
        source: 'manual_test',
      );
    }
    await _firestoreService.logGeoFenceEvent(
      clockNo: _clockNo!,
      eventType: isEntering ? 'enter' : 'exit',
      source: 'manual_test',
      notes: notes ?? 'Manual test from Diagnostics screen',
    );
    await prefs.setBool(_prefsLastKnownOnSite, isEntering);
    await _sendNotification(isEntering);
    if (isEntering) {
      await _startOnsiteMonitoring(boost: true);
    } else {
      await _startOffsiteReconcileOnly();
    }
  }
}
