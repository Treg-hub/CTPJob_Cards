import 'client_platform_service.dart';

ClientPlatformReport detectWebClient() {
  return const ClientPlatformReport(
    clientPlatform: 'web',
    clientDevice: 'unknown',
    notificationDelivery: 'push',
  );
}