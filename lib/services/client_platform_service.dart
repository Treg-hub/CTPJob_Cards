import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import 'firestore_service.dart';

import 'client_platform_detect_stub.dart'
    if (dart.library.html) 'client_platform_detect_web.dart' as detect;

/// Client-reported platform snapshot stored on `employees` via
/// [FirestoreService.updateMyPresence] / `updateEmployeePresence`.
class ClientPlatformReport {
  final String clientPlatform;
  final String clientDevice;
  final String notificationDelivery;

  const ClientPlatformReport({
    required this.clientPlatform,
    required this.clientDevice,
    required this.notificationDelivery,
  });

  Map<String, dynamic> toPresencePayload() => {
        'clientPlatform': clientPlatform,
        'clientDevice': clientDevice,
        'notificationDelivery': notificationDelivery,
      };

  bool get isInboxOnly => notificationDelivery == 'inbox_only';
}

class ClientPlatformService {
  static final ClientPlatformService _instance = ClientPlatformService._internal();
  factory ClientPlatformService() => _instance;
  ClientPlatformService._internal();

  ClientPlatformReport currentReport() {
    if (!kIsWeb) {
      return const ClientPlatformReport(
        clientPlatform: 'android',
        clientDevice: 'android',
        notificationDelivery: 'push',
      );
    }
    return detect.detectWebClient();
  }

  /// Best-effort sync so CF can park iPhone web users to notification_inbox.
  Future<void> syncToFirestore() async {
    try {
      final report = currentReport();
      await FirestoreService().updateMyPresence(
        clientPlatform: report.clientPlatform,
        clientDevice: report.clientDevice,
        notificationDelivery: report.notificationDelivery,
      );
      debugPrint(
        'Client platform synced: ${report.clientPlatform}/${report.clientDevice} '
        'delivery=${report.notificationDelivery}',
      );
    } catch (e) {
      debugPrint('Client platform sync failed (non-fatal): $e');
    }
  }
}