import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'firestore_service.dart';
import 'notification_service.dart';

const String locationTaskName = "ctp_location_check_task";

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
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
        lat = settingsDoc.data()?['latitude'] ?? lat;
        lng = settingsDoc.data()?['longitude'] ?? lng;
        radius = settingsDoc.data()?['radius']?.toDouble() ?? radius;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 15),
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
      await bg.BackgroundGeolocation.removeGeofences();

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
      ));

      await bg.BackgroundGeolocation.addGeofence(bg.Geofence(
        identifier: "company_site",
        latitude: -29.994938052011612,
        longitude: 30.939421740548614,
        radius: 800,
      ));

      bg.BackgroundGeolocation.onGeofence(_handleGeofenceEvent);
      bg.BackgroundGeolocation.onLocation(_handleLocationUpdate);
      await bg.BackgroundGeolocation.start();

      await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

      await Workmanager().registerPeriodicTask(
        locationTaskName,
        locationTaskName,
        frequency: const Duration(minutes: 30),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
      );

      _isInitialized = true;
      debugPrint('✅ Hybrid started: Native Geofence + WorkManager');
    } catch (e) {
      debugPrint('Hybrid monitoring failed: $e');
    }
  }

  Future<void> stopNativeMonitoring() async {
    if (kIsWeb) return;
    await bg.BackgroundGeolocation.stop();
    await Workmanager().cancelByUniqueName(locationTaskName);
    _isInitialized = false;
    debugPrint('🛑 Hybrid monitoring stopped');
  }

  void _handleGeofenceEvent(bg.GeofenceEvent event) async {
    final isEntering = event.action == 'ENTER';
    final eventType = isEntering ? 'enter' : 'exit';

    await _logGeoFenceEvent(eventType: eventType, source: 'native_geofence');
    await _updateFirestore(isEntering);
    await _sendNotification(isEntering);
  }

  void _handleLocationUpdate(bg.Location location) {
    debugPrint('📍 Location update received');
  }

  Future<void> checkCurrentLocation() async {
    try {
      final settingsDoc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('geofence')
          .get();

      double lat = -29.994938052011612;
      double lng = 30.939421740548614;
      double radius = 800;

      if (settingsDoc.exists) {
        lat = settingsDoc.data()?['latitude'] ?? lat;
        lng = settingsDoc.data()?['longitude'] ?? lng;
        radius = settingsDoc.data()?['radius']?.toDouble() ?? radius;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 15),
      );

      final onSite = Geolocator.distanceBetween(lat, lng, pos.latitude, pos.longitude) <= radius;

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
      debugPrint('Manual check failed: $e');
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
  }
}