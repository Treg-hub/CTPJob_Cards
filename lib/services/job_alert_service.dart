import 'package:flutter/services.dart';

class JobAlertService {
  static const MethodChannel _channel = MethodChannel('job_alert_channel');

  static Future<void> triggerUrgentAlert({
    required String jobCardNumber,
    required String description,
    String? location,      // ← department > area > location > part
    String? createdBy,
    String? priority,
    String? dueDate,
  }) async {
    try {
      await _channel.invokeMethod('triggerUrgentAlert', {
        'jobCardNumber': jobCardNumber,
        'description': description,
        'location': location ?? 'Not specified',
        'createdBy': createdBy ?? 'Manager',
        'priority': priority ?? '5',
        'dueDate': dueDate ?? 'ASAP',
      });
    } on PlatformException catch (e) {
      throw 'Failed to trigger urgent alert: ${e.message}';
    }
  }
}