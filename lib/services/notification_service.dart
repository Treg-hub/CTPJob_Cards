import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'job_alert_service.dart';

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  bool _isAppInForeground = true;
  late final _AppLifecycleObserver _lifecycleObserver;

  NotificationService() {
    _lifecycleObserver = _AppLifecycleObserver(this);
  }

  // ==================== PERMISSIONS ====================
  Future<void> _requestPermissions() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true, badge: true, sound: true,
      );
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
    final status = await Permission.systemAlertWindow.status;
    if (!status.isGranted) await openAppSettings();
  }

  // ==================== CHANNELS ====================
  Future<void> _createNotificationChannels() async {
    if (!Platform.isAndroid) return;

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(AndroidNotificationChannel(
      'normal_channel', 'Normal Job Notifications',
      description: 'Standard notifications for job card assignments',
      importance: Importance.high, enableVibration: true, playSound: true,
    ));

    await androidPlugin?.createNotificationChannel(AndroidNotificationChannel(
      'medium_channel', 'Medium-High Job Notifications',
      description: 'Loud notifications for priority 4 jobs',
      importance: Importance.high, enableVibration: true, playSound: true,
      sound: const RawResourceAndroidNotificationSound('escalation_alert'),
    ));

    await androidPlugin?.createNotificationChannel(AndroidNotificationChannel(
      'persistent_banner_channel', 'Persistent Job Alerts',
      description: 'Non-intrusive persistent banner for Priority 5 (foreground)',
      importance: Importance.high, enableVibration: true, playSound: true,
      sound: const RawResourceAndroidNotificationSound('escalation_alert'),
      vibrationPattern: Int64List.fromList([0, 300, 150, 300]),
    ));

    await androidPlugin?.createNotificationChannel(AndroidNotificationChannel(
      'full_channel', 'Full-Loud Job Notifications',
      description: 'Maximum priority notifications for priority 5 jobs (background only)',
      importance: Importance.max, bypassDnd: true, playSound: true,
      sound: const RawResourceAndroidNotificationSound('escalation_alert'),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1500, 500, 1500, 500, 1500, 500, 1500]),
      audioAttributesUsage: AudioAttributesUsage.alarm,
    ));

    debugPrint('All notification channels created successfully');
  }

  // ==================== SHOW NOTIFICATION ====================
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    required String level,
    String jobCardNumber = "unknown",
    String? location,
    String? createdBy,
    String? priority,
    String? dueDate,
  }) async {
    if (kIsWeb) return;

    late AndroidNotificationDetails androidDetails;
    final bool isForeground = _isAppInForeground;
    final bool isPriority5 = level == 'full-loud' || (priority != null && priority == '5');

    if (isPriority5 && isForeground) {
      androidDetails = AndroidNotificationDetails(
        'persistent_banner_channel', 'Persistent Job Alerts',
        icon: '@mipmap/ic_launcher',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('escalation_alert'),
        vibrationPattern: Int64List.fromList([0, 250, 100, 250]),
        ongoing: true,
        autoCancel: false,
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.message,
        color: const Color(0xFFFF0000),
        ledColor: const Color(0xFFFF0000),
        ledOnMs: 500,
        ledOffMs: 500,
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: location != null ? '📍 $location' : null,
        ),
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction('assign_self', 'Assign Self'),
          AndroidNotificationAction('view_job', 'View Job'),
        ],
      );
    } else if (isPriority5) {
      androidDetails = AndroidNotificationDetails(
        'full_channel', 'Full-Loud Job Notifications',
        icon: '@mipmap/ic_launcher',
        importance: Importance.max,
        priority: Priority.max,
        enableVibration: true,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('escalation_alert'),
        vibrationPattern: Int64List.fromList([0, 1500, 500, 1500, 500, 1500, 500, 1500]),
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        ongoing: true,
        visibility: NotificationVisibility.public,
        color: const Color(0xFFFF0000),
        ledColor: const Color(0xFFFF0000),
        ledOnMs: 500,
        ledOffMs: 500,
        styleInformation: BigTextStyleInformation(body),
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction('assign_self', 'Assign Self'),
          AndroidNotificationAction('view_job', 'View Job'),
        ],
      );
    } else if (level == 'medium-high') {
      androidDetails = AndroidNotificationDetails(
        'medium_channel', 'Medium-High Job Notifications',
        icon: '@mipmap/ic_launcher',
        importance: Importance.high, priority: Priority.high,
        enableVibration: true, playSound: true,
        sound: const RawResourceAndroidNotificationSound('escalation_alert'),
        vibrationPattern: Int64List.fromList([0, 800, 300, 800, 300, 800]),
        ongoing: true,
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.message,
        color: const Color(0xFFFF9800),
        ledColor: const Color(0xFFFF9800),
        ledOnMs: 500, ledOffMs: 500,
        styleInformation: BigTextStyleInformation(body),
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction('assign_self', 'Assign Self'),
          AndroidNotificationAction('view_job', 'View Job'),
        ],
      );
    } else {
      androidDetails = AndroidNotificationDetails(
        'normal_channel', 'Normal Job Notifications',
        icon: '@mipmap/ic_launcher',
        importance: Importance.high, priority: Priority.high,
        enableVibration: true, playSound: true,
        vibrationPattern: Int64List.fromList([0, 250, 100, 250]),
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.message,
        color: const Color(0xFF0000FF),
        ledColor: const Color(0xFF0000FF),
        ledOnMs: 500, ledOffMs: 500,
        styleInformation: BigTextStyleInformation(body),
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction('assign_self', 'Assign Self'),
          AndroidNotificationAction('view_job', 'View Job'),
        ],
      );
    }

    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: androidDetails),
      payload: jobCardNumber,
    );
  }

  // ==================== INITIALIZE ====================
  Future<void> initialize() async {
    if (kIsWeb) return;

    await _requestPermissions();
    await _createNotificationChannels();
    await requestAllCriticalPermissions();

    WidgetsBinding.instance.addObserver(_lifecycleObserver);

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
  }

  // ==================== FOREGROUND MESSAGE HANDLER ====================
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final level = message.data['notificationLevel'] ?? 'normal';
    final title = message.data['title'] ?? message.notification?.title ?? 'New Job Notification';
    final body = message.data['body'] ?? message.notification?.body ?? 'You have a new job assignment';
    final jobCardNumber = message.data['jobCardNumber'] ?? '0000';
    final location = message.data['location'];
    final createdBy = message.data['createdBy'];
    final priority = message.data['priority'];
    final dueDate = message.data['dueDate'];

    debugPrint('📩 Foreground message | Level: $level | Priority: $priority | Foreground: $_isAppInForeground');

    if ((level == 'full-loud' || priority == '5') && !_isAppInForeground) {
      try {
        await JobAlertService.triggerUrgentAlert(
          jobCardNumber: jobCardNumber,
          description: body,
          location: location,           // department > area > location > part
          createdBy: createdBy,
          priority: priority,
          dueDate: dueDate,
        );
        debugPrint('🚨 Full-screen urgent alert triggered (background)');
      } catch (e) {
        debugPrint('JobAlertService failed: $e');
      }
    }

    await _showLocalNotification(
      title: title,
      body: body,
      level: level,
      jobCardNumber: jobCardNumber,
      location: location,
      createdBy: createdBy,
      priority: priority,
      dueDate: dueDate,
    );
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('App opened from notification: ${message.data}');
  }

  // ==================== TEST METHODS ====================
  Future<void> testFullscreenNotification() async {
    await _showLocalNotification(
      title: "TEST - URGENT JOB",
      body: "This is a test full-screen notification (Priority 5)",
      level: "full-loud",
    );
  }

  Future<void> testPersistentBanner() async {
    _isAppInForeground = true;
    await _showLocalNotification(
      title: "TEST - PERSISTENT BANNER",
      body: "This should be a non-intrusive persistent banner (Priority 5 foreground)",
      level: "full-loud",
      priority: "5",
    );
  }

  // ==================== PUBLIC METHODS ====================
  Future<String?> getToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        debugPrint('✅ FCM Token: ${token.substring(0, 20)}...');
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
    if (recipientToken.isEmpty) return;
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'africa-south1')
          .httpsCallable('sendJobAssignmentNotification');

      await callable.call({
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
      });
      debugPrint('✅ Notification sent successfully');
    } catch (e) {
      debugPrint('❌ Error sending notification: $e');
      rethrow;
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
    required String notificationType,
    required String assigneeName,
    int? priority,
  }) async {
    if (recipientToken.isEmpty) return;
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'africa-south1')
          .httpsCallable('sendCreatorNotification');

      await callable.call({
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
      });
      debugPrint('✅ Creator notification sent successfully');
    } catch (e) {
      debugPrint('❌ Error sending creator notification: $e');
      rethrow;
    }
  }

  Future<void> refreshToken() async {
    try {
      final token = await getToken();
      if (token == null) throw Exception('Failed to refresh FCM token');
      debugPrint('✅ FCM Token refreshed');
    } catch (e) {
      debugPrint('❌ Error refreshing FCM token: $e');
      rethrow;
    }
  }

  Future<void> showOnSiteNotification({
    required String title,
    required String body,
    String level = 'normal',
  }) async {
    await _showLocalNotification(
      title: title,
      body: body,
      level: level,
    );
  }
}

// ==================== LIFECYCLE OBSERVER ====================
class _AppLifecycleObserver extends WidgetsBindingObserver {
  final NotificationService service;

  _AppLifecycleObserver(this.service);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    service._isAppInForeground = (state == AppLifecycleState.resumed);
    debugPrint('App lifecycle changed → Foreground: ${service._isAppInForeground}');
  }
}