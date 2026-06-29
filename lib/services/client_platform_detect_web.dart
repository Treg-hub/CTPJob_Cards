// Web-only stub — dart:html until package:web migration.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'client_platform_service.dart';

ClientPlatformReport detectWebClient() {
  final ua = html.window.navigator.userAgent.toLowerCase();
  final maxTouch = html.window.navigator.maxTouchPoints ?? 0;
  final isIpad = ua.contains('ipad') ||
      (ua.contains('macintosh') && maxTouch > 1);
  final isIphone = ua.contains('iphone');
  final isAndroid = ua.contains('android');

  if (isIphone || isIpad) {
    return ClientPlatformReport(
      clientPlatform: 'web',
      clientDevice: isIpad ? 'ipad' : 'iphone',
      notificationDelivery: 'inbox_only',
    );
  }
  if (isAndroid) {
    return const ClientPlatformReport(
      clientPlatform: 'web',
      clientDevice: 'android_browser',
      notificationDelivery: 'push',
    );
  }
  return const ClientPlatformReport(
    clientPlatform: 'web',
    clientDevice: 'desktop',
    notificationDelivery: 'push',
  );
}