import 'package:flutter/services.dart';

class JobAlertService {
  static const MethodChannel _channel = MethodChannel('job_alert_channel');

  /// Triggers full-screen urgent alert (only called from background)
  static Future<void> triggerUrgentAlert({
    required String jobCardNumber,
    required String description,
    String? location,
    String? createdBy,
    String? priority,
    String? clockNo,                    // ← ADD THIS PARAMETER
  }) async {
    try {
      await _channel.invokeMethod('triggerUrgentAlert', {
        'jobCardNumber': jobCardNumber,
        'description': description,
        'location': location ?? 'Location not specified',
        'createdBy': createdBy ?? 'Unknown',
        'priority': priority ?? '5',
        'clockNo': clockNo ?? 'unknown',
      });
    } on PlatformException catch (e) {
      throw 'Failed to trigger urgent alert: ${e.message}';
    }
  }
}