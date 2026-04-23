// lib/services/background_geofence_service.dart
// Replaces workmanager with flutter_background_service for periodic onsite checks.
// Runs every 30 minutes in background to verify isOnSite status.
// Battery efficient: medium accuracy, 10s timeout, conditional execution.

import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../firebase_options.dart';
import '../../models/employee.dart';
import 'firestore_service.dart';
import 'package:flutter/services.dart';

class BackgroundGeofenceService {
  // Company coordinates (duplicated from LocationService for self-containment)
  static const double COMPANY_LAT = -29.994938052011612;
  static const double COMPANY_LON = 30.939421740548614;
  static const double RADIUS_METERS = 2000.0;

  static Future<void> initializeService() async {
    // Early return on web: flutter_background_service unsupported on web platform.
    if (kIsWeb) return;

    final service = FlutterBackgroundService();

    /// Android config: background mode, no foreground notification
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        // this will be executed when app is in foreground/isolated
        onStart: onStart,
        // this will be executed when app is in background/terminated
        autoStart: true,
        autoStartOnBoot: true,
        isForegroundMode: false, // Pure background periodic task
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        // autoStart: true, // Not supported in iOS background service
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }
}

/// Entry point for background service
@pragma('vm:entry-point')
Future<bool> onStart(ServiceInstance service) async {
  // Initialize Firebase for background
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    // Optional: handle foreground/background switches
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Periodic onsite check every 30 minutes
  Timer.periodic(const Duration(minutes: 30), (timer) async {
    await _performGeofenceCheck();
  });

  return true;
}

/// iOS background handler
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  await _performGeofenceCheck();
  return true;
}

/// Core logic: mirror LocationService.backgroundCheck()
Future<void> _performGeofenceCheck() async {
  if (kIsWeb) return;

  try {
    // Get logged in clockNo
    final prefs = await SharedPreferences.getInstance();
    final clockNo = prefs.getString('loggedInClockNo');
    if (clockNo == null) return;

    // Get employee
    final firestoreService = FirestoreService();
    final emp = await firestoreService.getEmployee(clockNo);
    if (emp == null || !emp.isOnSite) return;

    // Check location permission briefly
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return;
    }

    // Get position
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
      timeLimit: const Duration(seconds: 10),
    );

    // Calculate distance
    final distance = Geolocator.distanceBetween(
      BackgroundGeofenceService.COMPANY_LAT,
      BackgroundGeofenceService.COMPANY_LON,
      pos.latitude,
      pos.longitude,
    );

    final onSite = distance <= BackgroundGeofenceService.RADIUS_METERS;

    // Update if off-site
    if (!onSite) {
      final updatedEmp = emp.copyWith(isOnSite: false);
      await firestoreService.updateEmployee(updatedEmp);
    }
  } catch (e) {
    debugPrint('Background geofence check failed: $e');
  }
}