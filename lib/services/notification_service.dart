import 'dart:io' show Platform;
import 'dart:typed_data' show Int64List;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'job_alert_service.dart';

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  // ==================== PERMISSIONS ====================
  Future<void> _requestPermissions() async {
    try {
      final settings = await _messaging.requestPermission(alert: true, badge: true, sound: true);
      debugPrint('FCM Permission: ${settings.authorizationStatus}');
    } catch (e) {
      debugPrint('Error requesting FCM permissions: $e');
    }
  }

  Future<Map<String, bool>> checkAllCriticalPermissions() async {
    final results = <String, bool>{};

    results['post_notifications'] = await Permission.notification.isGranted;
    results['system_alert_window'] = await Permission.systemAlertWindow.isGranted;
    results['notification_policy'] = await Permission.accessNotificationPolicy.isGranted;
    results['ignore_battery'] = await Permission.ignoreBatteryOptimizations.isGranted;

    return results;
  }

  Future<void> requestAllCriticalPermissions() async {
    if (!Platform.isAndroid) return;

    await Permission.notification.request();
    await Permission.systemAlertWindow.request();
    await Permission.accessNotificationPolicy.request();
    await Permission.ignoreBatteryOptimizations.request();

    // Open settings if still missing
    final status = await Permission.systemAlertWindow.status;
    if (!status.isGranted) {
      await openAppSettings();
    }
  }

  // ==================== CHANNELS ====================
  Future<void> _createNotificationChannels() async {
    if (!Platform.isAndroid) return;

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    // Normal Channel
    await androidPlugin?.createNotificationChannel(AndroidNotificationChannel(
      'normal_channel',
      'Normal Job Notifications',
      description: 'Standard notifications for job card assignments',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    ));

    // Medium Channel
    await androidPlugin?.createNotificationChannel(AndroidNotificationChannel(
      'medium_channel',
      'Medium-High Job Notifications',
      description: 'Loud notifications for priority 4 jobs',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('escalation_alert'),
    ));

    // FULL CHANNEL - WITH CALL CATEGORY (Critical Fix)
    await androidPlugin?.createNotificationChannel(AndroidNotificationChannel(
      'full_channel',
      'Full-Loud Job Notifications',
      description: 'Maximum priority notifications for priority 5 jobs',
      importance: Importance.max,
      bypassDnd: true,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('escalation_alert'),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 5001, 500, 500, 500, 500]),
      audioAttributesUsage: AudioAttributesUsage.alarm,
    ));

    debugPrint('All notification channels created successfully');
  }

  // ==================== SHOW NOTIFICATION ====================
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    required String level,
  }) async {
    if (kIsWeb) return;

    late AndroidNotificationDetails androidDetails;

    switch (level) {
      case 'medium-high':
        androidDetails = AndroidNotificationDetails(
          'medium_channel',
          'Medium-High Job Notifications',
          icon: '@mipmap/ic_launcher',
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('escalation_alert'),
          vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
        );
        break;

      case 'full-loud':
        androidDetails = AndroidNotificationDetails(
          'full_channel',
          'Full-Loud Job Notifications',
          icon: '@mipmap/ic_launcher',
          importance: Importance.max,
          priority: Priority.max,
          enableVibration: true,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('escalation_alert'),
          vibrationPattern: Int64List.fromList([0, 500, 500, 500, 500, 500]),
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        );
        break;

      default:
        androidDetails = AndroidNotificationDetails(
          'normal_channel',
          'Normal Job Notifications',
          icon: '@mipmap/ic_launcher',
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
          playSound: true,
        );
    }

    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: androidDetails),
    );
  }

  // ==================== INITIALIZE ====================
  Future<void> initialize() async {
    if (kIsWeb) return;

    await _requestPermissions();
    await _createNotificationChannels();
    await requestAllCriticalPermissions(); // Auto-request on startup

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // Background messages are now handled by native FirebaseMessagingService
    // This avoids the MissingPluginException in background isolate
    // FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final level = message.data['notificationLevel'] ?? 'normal';
    final title = message.data['title'] ?? message.notification?.title ?? 'New Job Notification';
    final body = message.data['body'] ?? message.notification?.body ?? 'You have a new job assignment';

    // Show local notification for all levels
    _showLocalNotification(title: title, body: body, level: level);

    // Trigger native full-screen urgent alert for Priority 5 jobs (full-loud level)
    if (level == 'full-loud') {
      debugPrint('🔥 FULL-LOUD detected! Calling native service...');   // ← ADD THIS LINE
      try {
        await JobAlertService.triggerUrgentAlert(
          message.data['jobCardNumber']?.toString() ?? 'N/A',
          message.data['body'] ?? message.data['description'] ?? 'Urgent job assigned',
        );
        debugPrint('✅ Urgent alert triggered for job #${message.data['jobCardNumber'] ?? 'N/A'}');
      } catch (e) {
        debugPrint('❌ Error triggering urgent alert: $e');
      }
    }
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('App opened from notification: ${message.data}');
  }

  // ==================== TEST FULLSCREEN ====================
  Future<void> testFullscreenNotification() async {
    await _showLocalNotification(
      title: "TEST - URGENT JOB",
      body: "This is a test full-screen notification (Priority 5)",
      level: "full-loud",
    );
  }

  Future<String?> getToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        debugPrint('✅ FCM Token retrieved: ${token.substring(0, 20)}...');
        return token;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting FCM token: $e');
      return null;
    }
  }

  Future<void> sendJobAssignmentNotification({
    required String recipientToken,
    required String jobCardId,
    required int? jobCardNumber,
    required String operator,
    required String creator,
    required String department,
    required String area,
    required String machine,
    required String part,
    required String description,
    int? priority,
  }) async {
    if (recipientToken.isEmpty) {
      debugPrint('⚠️ No FCM token - skipping notification');
      return;
    }

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'africa-south1')
          .httpsCallable('sendJobAssignmentNotification');

      final params = {
        'recipientToken': recipientToken,
        'jobCardId': jobCardId,
        'jobCardNumber': jobCardNumber,
        'operator': operator,
        'creator': creator,
        'department': department,
        'area': area,
        'machine': machine,
        'part': part,
        'description': description,
        'priority': priority ?? 1,
      };

      await callable.call(params);
      debugPrint('✅ Notification sent successfully');
    } catch (e) {
      debugPrint('❌ Error sending notification: $e');
      throw Exception('Failed to send notification: $e');
    }
  }

  Future<void> sendCreatorNotification({
    required String recipientToken,
    required String jobCardId,
    required int? jobCardNumber,
    required String operator,
    required String creator,
    required String department,
    required String area,
    required String machine,
    required String part,
    required String description,
    required String notificationType, // 'self_assign' or 'closed'
    required String assigneeName,
    int? priority,
  }) async {
    if (recipientToken.isEmpty) {
      debugPrint('⚠️ No FCM token - skipping creator notification');
      return;
    }

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'africa-south1')
          .httpsCallable('sendCreatorNotification');

      final params = {
        'recipientToken': recipientToken,
        'jobCardId': jobCardId,
        'jobCardNumber': jobCardNumber,
        'operator': operator,
        'creator': creator,
        'department': department,
        'area': area,
        'machine': machine,
        'part': part,
        'description': description,
        'notificationType': notificationType,
        'assigneeName': assigneeName,
        'priority': priority ?? 1,
      };

      await callable.call(params);
      debugPrint('✅ Creator notification sent successfully');
    } catch (e) {
      debugPrint('❌ Error sending creator notification: $e');
      throw Exception('Failed to send creator notification: $e');
    }
  }

  Future<void> refreshToken() async {
    try {
      final token = await getToken();
      if (token == null) throw Exception('Failed to refresh FCM token');
      debugPrint('✅ FCM Token refreshed successfully');
    } catch (e) {
      debugPrint('❌ Error refreshing FCM token: $e');
      throw Exception('Failed to refresh FCM token: $e');
    }
  }

  Future<void> showOnSiteNotification({
    required String title,
    required String body,
  }) async {
    await _showLocalNotification(title: title, body: body, level: 'normal');
  }
}
