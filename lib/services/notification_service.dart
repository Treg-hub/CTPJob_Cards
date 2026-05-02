import 'dart:async';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

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
      importance: Importance.defaultImportance,
      enableVibration: true,
      playSound: true,
    ));

    await androidPlugin?.createNotificationChannel(AndroidNotificationChannel(
      'medium_channel', 'Medium Job Notifications',
      description: 'Notifications for priority 2 & 3 jobs',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('escalation_alert'),
      vibrationPattern: Int64List.fromList([0, 600, 200, 600]),
    ));

    await androidPlugin?.createNotificationChannel(AndroidNotificationChannel(
      'persistent_banner_channel', 'Persistent Job Alerts',
      description: 'Persistent banner for Priority 4 & 5 (when app is open)',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('escalation_alert'),
      vibrationPattern: Int64List.fromList([0, 800, 300, 800]),
    ));

    await androidPlugin?.createNotificationChannel(AndroidNotificationChannel(
      'full_channel', 'Full-Loud Job Notifications',
      description: 'Maximum priority full-screen alerts for priority 4 & 5',
      importance: Importance.max,
      bypassDnd: true,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('escalation_alert'),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1500, 500, 1500, 500, 1500, 500, 1500]),
      audioAttributesUsage: AudioAttributesUsage.alarm,
    ));

    debugPrint('All notification channels created successfully');
  }

  // ==================== SHOW NOTIFICATION WITH 3 BUTTONS ====================
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    required String level,
    String jobCardNumber = "unknown",
    String? location,
    String? createdBy,
    String? priority,
  }) async {
    if (kIsWeb) return;

    Color getPriorityColor(String? priority) {
      switch (priority) {
        case '5': return const Color(0xFFFF0000);
        case '4': return const Color(0xFFFF5722);
        case '3': case '2': return const Color(0xFFFF9800);
        default: return const Color(0xFF2196F3);
      }
    }

    final bool isHighPriority = level == 'full-loud' || (priority != null && (priority == '5' || priority == '4'));

    late AndroidNotificationDetails androidDetails;

    if (isHighPriority && _isAppInForeground) {
      // P4/P5 when app is OPEN → Persistent red/orange banner + 3 buttons
      androidDetails = AndroidNotificationDetails(
        'persistent_banner_channel', 'Persistent Job Alerts',
        icon: '@mipmap/ic_launcher',
        importance: Importance.max,
        priority: Priority.max,
        enableVibration: true,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('escalation_alert'),
        vibrationPattern: Int64List.fromList([0, 800, 300, 800]),
        ongoing: true,
        autoCancel: false,
        color: getPriorityColor(priority),
        colorized: true,
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.message,
        styleInformation: BigTextStyleInformation(body),
        actions: <AndroidNotificationAction>[
          const AndroidNotificationAction('assign_self', 'Assign Self'),
          const AndroidNotificationAction('busy', 'Busy'),
          const AndroidNotificationAction('dismiss', 'Dismiss'),
        ],
      );
    } else if (isHighPriority) {
      // P4/P5 when app is NOT visible → Full-screen (handled by native AlarmReceiver)
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
        autoCancel: false,
        visibility: NotificationVisibility.public,
        color: getPriorityColor(priority),
        colorized: true,
        styleInformation: BigTextStyleInformation(body),
        actions: <AndroidNotificationAction>[
          const AndroidNotificationAction('assign_self', 'Assign Self'),
          const AndroidNotificationAction('busy', 'Busy'),
          const AndroidNotificationAction('dismiss', 'Dismiss'),
        ],
      );
    } else if (level == 'medium-high' || level == 'medium') {
      androidDetails = AndroidNotificationDetails(
        'medium_channel', 'Medium Job Notifications',
        icon: '@mipmap/ic_launcher',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('escalation_alert'),
        vibrationPattern: Int64List.fromList([0, 600, 200, 600]),
        ongoing: true,
        autoCancel: false,
        visibility: NotificationVisibility.public,
        color: getPriorityColor(priority),
        colorized: true,
        styleInformation: BigTextStyleInformation(body),
        actions: <AndroidNotificationAction>[
          const AndroidNotificationAction('assign_self', 'Assign Self'),
          const AndroidNotificationAction('busy', 'Busy'),
          const AndroidNotificationAction('dismiss', 'Dismiss'),
        ],
      );
    } else {
      androidDetails = AndroidNotificationDetails(
        'normal_channel', 'Normal Job Notifications',
        icon: '@mipmap/ic_launcher',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        enableVibration: true,
        playSound: true,
        visibility: NotificationVisibility.public,
        color: getPriorityColor(priority),
        colorized: true,
        styleInformation: BigTextStyleInformation(body),
        actions: <AndroidNotificationAction>[
          const AndroidNotificationAction('assign_self', 'Assign Self'),
          const AndroidNotificationAction('busy', 'Busy'),
          const AndroidNotificationAction('dismiss', 'Dismiss'),
        ],
      );
    }

    await _localNotifications.show(
      id: int.tryParse(jobCardNumber) ?? 9999,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: androidDetails),
      payload: '$jobCardNumber|${createdBy ?? "Unknown"}',
    );
  }

  // ==================== HANDLE 3 BUTTON ACTIONS ====================
  void _handleNotificationAction(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;

    final parts = payload.split('|');
    final jobCardNumber = parts[0];
    final operator = parts.length > 1 ? parts[1] : 'Unknown';

    switch (response.actionId) {
      case 'assign_self':
        _assignJobToCurrentUser(jobCardNumber);
        break;
      case 'busy':
        _sendBusyNotificationToOperator(jobCardNumber, operator);
        break;
      case 'dismiss':
        _logDismissedAlert(jobCardNumber, operator);
        break;
      default:
        // Tap on notification body
        debugPrint('Open job card: $jobCardNumber');
    }
  }

  Future<void> _assignJobToCurrentUser(String jobCardNumber) async {
    debugPrint('Assign Self tapped for job $jobCardNumber');
    // TODO: Add your Firestore update logic here or call MethodChannel
  }

  Future<void> _sendBusyNotificationToOperator(String jobCardNumber, String operator) async {
    debugPrint('Busy tapped for job $jobCardNumber - notifying operator: $operator');
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'africa-south1')
          .httpsCallable('sendBusyNotification');
      await callable.call({
        'jobCardNumber': jobCardNumber,
        'originalOperator': operator,
        'busyUserName': 'Current User', // TODO: Get real name
      });
      debugPrint('✅ Busy notification sent via Cloud Function');
    } catch (e) {
      debugPrint('❌ Failed to send busy notification: $e');
    }
  }

  Future<void> _logDismissedAlert(String jobCardNumber, String operator) async {
    debugPrint('Dismiss tapped for job $jobCardNumber');
    // TODO: Add Firestore write to dismissedAlerts collection
  }

  // ==================== INITIALIZE ====================
  Future<void> initialize() async {
    if (kIsWeb) return;

    await _requestPermissions();
    await _createNotificationChannels();
    await requestAllCriticalPermissions();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);

      await _localNotifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: _handleNotificationAction,
  );

  FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
}

  // ==================== FOREGROUND MESSAGE HANDLER ====================
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final level = message.data['notificationLevel'] ?? 'normal';
    final title = message.data['title'] ?? message.notification?.title ?? 'New Job Notification';
    final body = message.data['body'] ?? message.notification?.body ?? 'You have a new job assignment';
    final jobCardNumber = message.data['jobCardNumber'] ?? '0000';
    final priority = message.data['priority'] ?? '1';
    final createdBy = message.data['createdBy'] ?? message.data['operator'] ?? 'Unknown';
    final department = message.data['department'] ?? '';
    final area = message.data['area'] ?? '';
    final machine = message.data['machine'] ?? '';
    final part = message.data['part'] ?? '';

    debugPrint('📩 Foreground message | Level: $level | Priority: $priority | Foreground: $_isAppInForeground');

    await _showLocalNotification(
      title: title,
      body: body,
      level: level,
      jobCardNumber: jobCardNumber,
      location: [department, area, machine, part].where((e) => e.isNotEmpty).join(' > '),
      createdBy: createdBy,
      priority: priority,
    );
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('App opened from notification: ${message.data}');
  }

  // ==================== TEST METHODS ====================
  Future<void> testPersistentBanner() async {
    _isAppInForeground = true;
    await _showLocalNotification(
      title: "TEST - PERSISTENT BANNER (P5)",
      body: "This should be a red persistent banner with 3 buttons",
      level: "full-loud",
      priority: "5",
    );
  }

  Future<void> testFullscreenNotification() async {
    await _showLocalNotification(
      title: "TEST - FULL SCREEN (P5)",
      body: "This should trigger full-screen alert",
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
    await _showLocalNotification(title: title, body: body, level: level);
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