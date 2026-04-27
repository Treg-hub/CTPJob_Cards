import 'package:flutter/services.dart';

class JobAlertService {
  static const MethodChannel _channel = MethodChannel('job_alert_channel');

  static Future<void> triggerUrgentAlert(String jobCardNumber, String description) async {
    try {
      await _channel.invokeMethod('triggerUrgentAlert', {
        'jobCardNumber': jobCardNumber,
        'description': description,
      });
    } on PlatformException catch (e) {
      throw 'Failed to trigger urgent alert: ${e.message}';
    }
  }
}