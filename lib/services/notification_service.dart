import 'dart:io' show Platform;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    if (kIsWeb) return;

    // Request permissions
    await _requestPermissions();

    // Initialize local notifications for Android
    if (Platform.isAndroid) {
      // Create notification channel
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'job_cards_channel',
        'Job Card Notifications',
        description: 'Notifications for job card assignments',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    // Set up message handlers
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
  }

  Future<void> _requestPermissions() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
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

    if (message.notification != null) {
      // Show local notification for foreground messages
      _showLocalNotification(
        title: message.notification!.title ?? 'New Notification',
        body: message.notification!.body ?? 'You have a new notification',
      );
    }
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('📱 Message opened app: ${message.messageId}');

    if (message.data['click_action'] == 'FLUTTER_NOTIFICATION_CLICK') {
      // Handle navigation to assigned jobs screen
      // This will be handled by the UI layer
    }
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'job_cards_channel',
      'Job Card Notifications',
      channelDescription: 'Notifications for job card assignments',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
    );

    const NotificationDetails details = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000, // Unique ID
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
      };

      debugPrint('🚀 Calling sendJobAssignmentNotification with:');
      debugPrint('  recipientToken len: ${recipientToken.length} preview: ${recipientToken.substring(0, 50)}...');
      debugPrint('  Full map keys: ${params.keys}');

      await callable.call(params);

      debugPrint('✅ Notification sent successfully');
    } catch (e) {
      debugPrint('❌ Error sending notification: $e');
      throw Exception('Failed to send notification: $e');
    }
  }

  Future<void> refreshToken() async {
    try {
      final token = await getToken();
      if (token == null) {
        throw Exception('Failed to refresh FCM token');
      }
      debugPrint('✅ FCM Token refreshed successfully');
    } catch (e) {
      debugPrint('❌ Error refreshing FCM token: $e');
      throw Exception('Failed to refresh FCM token: $e');
    }
  }
}