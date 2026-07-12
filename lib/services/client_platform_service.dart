import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';

import 'firestore_service.dart';

import 'client_platform_detect_stub.dart'
    if (dart.library.html) 'client_platform_detect_web.dart' as detect;

/// Client-reported platform + app version stored on `employees` via
/// [FirestoreService.updateMyPresence] / `updateEmployeePresence`.
///
/// Admin → On Site uses [clientAppVersion] / [clientBuildNumber] to see who
/// still needs a soft update before a `minSupportedBuild` hard cutoff.
class ClientPlatformReport {
  final String clientPlatform;
  final String clientDevice;
  final String notificationDelivery;
  final String? clientAppVersion;
  final String? clientBuildNumber;

  const ClientPlatformReport({
    required this.clientPlatform,
    required this.clientDevice,
    required this.notificationDelivery,
    this.clientAppVersion,
    this.clientBuildNumber,
  });

  Map<String, dynamic> toPresencePayload() => {
        'clientPlatform': clientPlatform,
        'clientDevice': clientDevice,
        'notificationDelivery': notificationDelivery,
        if (clientAppVersion != null) 'clientAppVersion': clientAppVersion,
        if (clientBuildNumber != null) 'clientBuildNumber': clientBuildNumber,
      };

  bool get isInboxOnly => notificationDelivery == 'inbox_only';
}

class ClientPlatformService {
  static final ClientPlatformService _instance = ClientPlatformService._internal();
  factory ClientPlatformService() => _instance;
  ClientPlatformService._internal();

  Future<ClientPlatformReport> currentReport() async {
    String? version;
    String? build;
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build = info.buildNumber;
    } catch (e) {
      debugPrint('PackageInfo read failed (non-fatal): $e');
    }

    if (!kIsWeb) {
      return ClientPlatformReport(
        clientPlatform: 'android',
        clientDevice: 'android',
        notificationDelivery: 'push',
        clientAppVersion: version,
        clientBuildNumber: build,
      );
    }
    final web = detect.detectWebClient();
    return ClientPlatformReport(
      clientPlatform: web.clientPlatform,
      clientDevice: web.clientDevice,
      notificationDelivery: web.notificationDelivery,
      clientAppVersion: version,
      clientBuildNumber: build,
    );
  }

  /// Best-effort sync so CF can park iPhone web users to notification_inbox
  /// and Admin On-site can show which APK build each employee last opened.
  Future<void> syncToFirestore() async {
    try {
      final report = await currentReport();
      await FirestoreService().updateMyPresence(
        clientPlatform: report.clientPlatform,
        clientDevice: report.clientDevice,
        notificationDelivery: report.notificationDelivery,
        clientAppVersion: report.clientAppVersion,
        clientBuildNumber: report.clientBuildNumber,
      );
      debugPrint(
        'Client platform synced: ${report.clientPlatform}/${report.clientDevice} '
        'v${report.clientAppVersion ?? '?'}+${report.clientBuildNumber ?? '?'} '
        'delivery=${report.notificationDelivery}',
      );
    } catch (e) {
      debugPrint('Client platform sync failed (non-fatal): $e');
    }
  }
}
