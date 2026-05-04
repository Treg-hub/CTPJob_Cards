import 'dart:async' show Timer;
import 'dart:io' show Platform;
import 'dart:typed_data' show Int64List;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:torch_light/torch_light.dart';
import 'job_alert_service.dart';
import '../main.dart' show currentEmployee;

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

  // ==================== HANDLE ACTION BUTTONS ====================
  Future<void> _handleNotificationAction(NotificationResponse response) async {
    final String? actionId = response.actionId;
    final String? payload = response.payload;

    if (actionId == null || payload == null) return;

    final user = currentEmployee;
    if (user == null) {
      debugPrint('❌ No logged in user for notification action');
      return;
    }

    final clockNo = user.clockNo;
    final name = user.name ?? 'Unknown User';

    debugPrint('🔔 Action: $actionId for job #$payload by $name ($clockNo)');

    try {
      if (actionId == 'assign_self') {
        final query = await FirebaseFirestore.instance
            .collection('job_cards')
            .where('jobCardNumber', isEqualTo: int.tryParse(payload))
            .limit(1)
            .get();

        if (query.docs.isEmpty) {
          debugPrint('❌ Job not found');
          return;
        }

        final doc = query.docs.first;
        final jobData = doc.data();

        await doc.reference.update({
          'assignedTo': clockNo,
          'assignedNames': name,
          'assignedClockNos': clockNo,
          'status': 'open',
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        });

        debugPrint('✅ Job #$payload assigned to $name');

        // Notify creator
        final creatorClockNo = jobData['operatorClockNo'];
        if (creatorClockNo != null) {
          final creatorDoc = await FirebaseFirestore.instance
              .collection('employees')
              .doc(creatorClockNo)
              .get();

          if (creatorDoc.exists && creatorDoc.data()?['fcmToken'] != null) {
            await FirebaseFunctions.instance
                .httpsCallable('sendCreatorNotification')
                .call({
              'recipientToken': creatorDoc.data()!['fcmToken'],
              'jobCardId': doc.id,
              'jobCardNumber': int.parse(payload),
              'notificationType': 'self_assign',
              'assigneeName': name,
              'area': jobData['area'] ?? '',
              'description': jobData['description'] ?? '',
              'priority': jobData['priority'] ?? 1,
              'initiatedByClockNo': clockNo,
              'initiatedByName': name,
            });
          }
        }
      } 
      else if (actionId == 'busy' || actionId == 'dismiss') {
        await FirebaseFirestore.instance.collection('notifications').add({
          'jobCardNumber': int.tryParse(payload),
          'triggeredBy': actionId,
          'initiatedByClockNo': clockNo,
          'initiatedByName': name,
          'timestamp': FieldValue.serverTimestamp(),
          'level': 'normal',
        });
        debugPrint('✅ Logged $actionId for job #$payload');
      }
    } catch (e) {
      debugPrint('❌ Error in action $actionId: $e');
    }
  }

  // ==================== SHOW LOCAL NOTIFICATION ====================
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

    final bool isHighPriority = level == 'full-loud' || (priority != null && (priority == '5' || priority == '4'));

    late AndroidNotificationDetails androidDetails;

    if (isHighPriority && _isAppInForeground) {
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
        color: _getPriorityColor(priority),
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
        color: _getPriorityColor(priority),
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
        color: _getPriorityColor(priority),
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
        color: _getPriorityColor(priority),
        colorized: true,
        styleInformation: BigTextStyleInformation(body),
        actions: <AndroidNotificationAction>[
          const AndroidNotificationAction('assign_self', 'Assign Self'),
          const AndroidNotificationAction('busy', 'Busy'),
          const AndroidNotificationAction('dismiss', 'Dismiss'),
        ],
      );
    }

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      notificationDetails,
      payload: jobCardNumber,
    );
  }

  Color _getPriorityColor(String? priority) {
    switch (priority) {
      case '5': return const Color(0xFFFF0000);
      case '4': return const Color(0xFFFF5722);
      case '3': case '2': return const Color(0xFFFF9800);
      default: return const Color(0xFF2196F3);
    }
  }

  // ==================== INITIALIZE ====================
  Future<void> initialize() async {
    await _requestPermissions();
    await _createNotificationChannels();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleNotificationAction,
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Foreground message: ${message.notification?.title}');
    });

    debugPrint('✅ NotificationService initialized with working buttons');
  }

  Future<void> refreshToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) debugPrint('✅ FCM Token refreshed');
    } catch (e) {
      debugPrint('❌ Error refreshing token: $e');
    }
  }
}