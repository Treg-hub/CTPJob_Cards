import 'dart:async';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
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
  static const double RADIUS_METERS = 2000.0;

  final MethodChannel _channel = const MethodChannel('ctp/geofence');
  String? _clockNo;
  final FirestoreService _firestoreService = FirestoreService();
  final NotificationService _notificationService = NotificationService();

  Future<void> startNativeMonitoring(String clockNo) async {
    _clockNo = clockNo;
    await _requestPermissions();
    await _notificationService.initialize();
    await _channel.invokeMethod('startGeofence', {
      'clockNo': clockNo,
      'lat': COMPANY_LAT,
      'lng': COMPANY_LON,
      'radius': RADIUS_METERS,
    });
    await _checkFallback();
    print('Geofence started for $clockNo');
  }

  Future<void> stopNativeMonitoring() async {
    await _channel.invokeMethod('stopGeofence');
    print('Geofence stopped');
  }

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
      Position? pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        bool onSite = Geolocator.distanceBetween(COMPANY_LAT, COMPANY_LON, pos.latitude, pos.longitude) <= RADIUS_METERS;
        await _updateFirestore(onSite);
        await _sendNotification(onSite);
        print('Fallback check: onSite=$onSite');
      }
    } catch (e) {
      print('Fallback check failed: $e');
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onGeofenceEvent':
        final entering = call.arguments['entering'] as bool;
        await _updateFirestore(entering);
        await _sendNotification(entering);
        print('Geofence event: entering=$entering');
        break;
      default:
        throw MissingPluginException();
    }
  }

  Future<void> _updateFirestore(bool onSite) async {
    if (_clockNo == null) return;
    final emp = await _firestoreService.getEmployee(_clockNo!);
    if (emp != null) {
      final updated = emp.copyWith(isOnSite: onSite);
      await _firestoreService.updateEmployee(updated);
    }
  }

  Future<void> _sendNotification(bool onSite) async {
    final title = onSite ? '✅ On-Site Detected' : '📍 Left Site Area';
    final body = onSite ? 'Within 2km of CTP. Ready for jobs.' : 'Off-site. Filtering updated.';
    await _notificationService.showOnSiteNotification(title: title, body: body);
  }
}
