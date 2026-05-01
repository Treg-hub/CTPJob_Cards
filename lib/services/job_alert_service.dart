import 'package:flutter/services.dart';

class JobAlertService {
  static const MethodChannel _channel = MethodChannel('job_alert_channel');

  /// Triggers full-screen urgent alert (only called from background)
  static Future<void> triggerUrgentAlert({
    required String jobCardNumber,
    required String description,
    String? location,           // e.g. "Mechanical > Workshop A > Lathe 3 > Spindle Bearing"
    String? createdBy,
    String? priority,
  }) async {
    try {
      await _channel.invokeMethod('triggerUrgentAlert', {
        'jobCardNumber': jobCardNumber,
        'description': description,
        'location': location ?? 'Location not specified',
        'createdBy': createdBy ?? 'Unknown',
        'priority': priority ?? '5',
      });
    } on PlatformException catch (e) {
      throw 'Failed to trigger urgent alert: ${e.message}';
    }
  }
}