import 'dart:io' show Platform;
import 'dart:typed_data' show Int64List;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    if (kIsWeb) return;

    await _requestPermissions();

    // Initialize local notifications with multiple channels
    if (Platform.isAndroid) {
      const AndroidNotificationChannel normalChannel = AndroidNotificationChannel(
        'normal_channel',
        'Normal Job Notifications',
        description: 'Standard notifications for job card assignments',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      );

      const AndroidNotificationChannel mediumChannel = AndroidNotificationChannel(
        'medium_channel',
        'Medium-High Job Notifications',
        description: 'Loud notifications for priority 4 jobs',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('escalation_alert'),
      );

final AndroidNotificationChannel fullChannel = AndroidNotificationChannel(
  'full_channel',
  'Full-Loud Job Notifications',
  description: 'Maximum priority notifications for priority 5 jobs and urgent escalations',
  importance: Importance.max,
  bypassDnd: true,
  playSound: true,
  sound: RawResourceAndroidNotificationSound('escalation_alert'),
  enableVibration: true,
  vibrationPattern: Int64List.fromList([0, 500, 500, 500, 500, 500]),
  audioAttributesUsage: AudioAttributesUsage.alarm,
);

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(normalChannel);
      await androidPlugin?.createNotificationChannel(mediumChannel);
      await androidPlugin?.createNotificationChannel(fullChannel);

      // Request Do Not Disturb access (required for bypassDnd to work)
      final androidImplementation = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        final bool? granted = await androidImplementation.requestNotificationsPermission();

        if (granted == true) {
          // DND permission must be granted manually by the user
          // We will add a button or auto-open the settings screen in the next step
          debugPrint('Notification permission granted. User still needs to grant DND access manually.');
        }
      }
    }

    // Message handlers
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
  }

  Future<void> _requestPermissions() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('✅ Notification permissions granted');
      } else {
        debugPrint('⚠️ Notification permissions denied');
      }
    } catch (e) {
      debugPrint('❌ Error requesting notification permissions: $e');
    }
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

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('📨 Foreground message received: ${message.messageId}');
    debugPrint('📨 RAW FCM DATA RECEIVED: ${message.data}');

    // Handle both notification messages (with notification field) and data messages
    if (message.notification != null || message.data.isNotEmpty) {
      final level = message.data['notificationLevel'] ?? 'normal';
      debugPrint('Received notificationLevel: $level');

      final title = message.data['title'] ?? message.notification?.title ?? 'New Notification';
      final body = message.data['body'] ?? message.notification?.body ?? 'You have a new notification';

      _showLocalNotification(
        title: title,
        body: body,
        level: level,
      );
    }
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('📱 Message opened app: ${message.messageId}');
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    required String level,
  }) async {
    debugPrint('=== RECEIVED LEVEL: $level | Using channel: ${level == "full-loud" ? "full_channel" : "normal/medium"} ===');
    if (kIsWeb) return;

    late AndroidNotificationDetails androidDetails;
    switch (level) {
      case 'medium-high':
        androidDetails = AndroidNotificationDetails(
          'medium_channel',
          'Medium-High Job Notifications',
          channelDescription: 'Loud notifications for priority 4 jobs',
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('escalation_alert'),
          vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
        );
        break;
      case 'full-loud':
        androidDetails = AndroidNotificationDetails(
          'full_channel',
          'Full-Loud Job Notifications',
          channelDescription: 'Maximum priority notifications for priority 5 jobs',
          importance: Importance.max,
          priority: Priority.max,
          enableVibration: true,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('escalation_alert'),
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
          channelDescription: 'Standard notifications for job card assignments',
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
          playSound: true,
        );
    }

    final NotificationDetails details = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: details,
    );
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
}
