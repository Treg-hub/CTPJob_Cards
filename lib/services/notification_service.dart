import 'dart:io' show Platform;
import 'dart:typed_data' show Int64List;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show currentEmployee;

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

    final status = await Permission.systemAlertWindow.status;
    if (!status.isGranted) await openAppSettings();
  }

  // ==================== CHANNELS ====================
  Future<void> _createNotificationChannels() async {
    if (!Platform.isAndroid) return;

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    // Normal channel
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      'normal_channel', 'Normal Job Notifications',
      description: 'Standard notifications for job card assignments',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    ));

    // Medium channel
    await androidPlugin?.createNotificationChannel(AndroidNotificationChannel(
      'medium_channel', 'Medium Job Notifications',
      description: 'Notifications for priority 2 & 3 jobs',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('escalation_alert'),
      vibrationPattern: Int64List.fromList([0, 600, 200, 600]),
    ));

    // Persistent banner
    await androidPlugin?.createNotificationChannel(AndroidNotificationChannel(
      'persistent_banner_channel', 'Persistent Job Alerts',
      description: 'Persistent banner for Priority 4 & 5 (when app is open)',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('escalation_alert'),
      vibrationPattern: Int64List.fromList([0, 800, 300, 800]),
    ));

    // Full-loud channel (with DND bypass)
    await androidPlugin?.createNotificationChannel(AndroidNotificationChannel(
      'full_channel', 'Full-Loud Job Notifications',
      description: 'Maximum priority full-screen alerts for priority 4 & 5',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('escalation_alert'),
      vibrationPattern: Int64List.fromList([0, 1500, 500, 1500, 500, 1500, 500, 1500]),
      audioAttributesUsage: AudioAttributesUsage.alarm,
    ));

    debugPrint('All notification channels created successfully');
  }

  // ==================== HANDLE NOTIFICATION ACTION ====================
  Future<void> handleNotificationAction(NotificationResponse response) async {
    debugPrint('NotificationService _handleNotificationAction CALLED');
    debugPrint('   actionId: ${response.actionId}');
    debugPrint('   payload: ${response.payload}');

    final String? actionId = response.actionId;
    final String? payload = response.payload;

    if (actionId == null || payload == null) {
      debugPrint('   actionId or payload is null → returning early');
      return;
    }

    // Robust user loading (3 fallbacks)
    String clockNo = '';
    String name = 'Unknown User';

    if (currentEmployee != null) {
      clockNo = currentEmployee!.clockNo;
      name = currentEmployee!.name;
    } else {
      final prefs = await SharedPreferences.getInstance();
      clockNo = prefs.getString('loggedInClockNo') ?? '';
      name = prefs.getString('employeeName') ?? 'Unknown User';
    }

    if (clockNo.isEmpty) {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        try {
          final realClockNo = firebaseUser.uid.startsWith('employee_')
              ? firebaseUser.uid.substring(9)
              : firebaseUser.uid;

          final empDoc = await FirebaseFirestore.instance
              .collection('employees')
              .doc(realClockNo)
              .get();

          if (empDoc.exists) {
            clockNo = empDoc.data()?['clockNo'] ?? realClockNo;
            name = empDoc.data()?['name'] ?? 'Unknown User';
          } else {
            clockNo = realClockNo;
          }
        } catch (e) {
          debugPrint('   Firebase fallback failed: $e');
        }
      }
    }

    if (clockNo.isEmpty) {
      debugPrint('   FINAL RESULT: No logged in user found → returning early');
      return;
    }

    debugPrint('   FINAL USER: $name ($clockNo) for action: $actionId on job #$payload');

    try {
      if (actionId == 'assign_self') {

        debugPrint('   → Handling ASSIGN SELF for job #$payload');

        final query = await FirebaseFirestore.instance
            .collection('job_cards')
            .where('jobCardNumber', isEqualTo: int.tryParse(payload))
            .limit(1)
            .get();

        if (query.docs.isEmpty) {
          debugPrint('   Job not found in Firestore');
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

        debugPrint('   Job #$payload successfully assigned to $name');

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
              'machine': jobData['machine'] ?? '',
              'part': jobData['part'] ?? '',
              'description': jobData['description'] ?? '',
            });
          }
        }
      } else if (actionId == 'busy') {
        // Write to alertResponses so the Cloud Function onAlertResponseCreated:
        //   1. Notifies the job creator that this technician is busy
        //   2. Sets escalationStopped: true on the job card to halt escalation
        debugPrint('   → Handling BUSY for job #$payload by $name ($clockNo)');
        await FirebaseFirestore.instance.collection('alertResponses').add({
          'jobCardNumber': payload,
          'action': 'busy',
          'clockNo': clockNo,
          'userName': name,
          'timestamp': FieldValue.serverTimestamp(),
        });
        debugPrint('   Busy response written to alertResponses for job #$payload');
      } else if (actionId == 'dismiss') {
        debugPrint('   → Handling DISMISS for job #$payload by $name ($clockNo)');
        await FirebaseFirestore.instance.collection('alertResponses').add({
          'jobCardNumber': payload,
          'action': 'dismissed',
          'clockNo': clockNo,
          'userName': name,
          'timestamp': FieldValue.serverTimestamp(),
        });
        debugPrint('   Dismiss written to alertResponses for job #$payload');
      }
    } catch (e) {
      debugPrint('   Error handling action $actionId: $e');
    }
  }

  // ==================== SHOW LOCAL NOTIFICATION ====================
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    required String level,
    String jobCardNumber = "unknown",
  }) async {
    if (kIsWeb) return;

    late AndroidNotificationDetails androidDetails;

    switch (level) {
      case 'medium-high':
        androidDetails = AndroidNotificationDetails(
          'medium_channel', 'Medium Job Notifications',
          icon: '@mipmap/ic_launcher',
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('escalation_alert'),
          vibrationPattern: Int64List.fromList([0, 800, 300, 800]),
          ongoing: true,
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.message,
          color: const Color(0xFFFF9800),
        );
        break;

      case 'full-loud':
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
          // bypassDnd: true,           // ← Updated for v17+
        );
        break;

      default:
        androidDetails = const AndroidNotificationDetails(
          'normal_channel', 'Normal Job Notifications',
          icon: '@mipmap/ic_launcher',
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
          playSound: true,
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.message,
          color: Color(0xFF0000FF),
        );
    }

    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch % 2147483647,
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

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: handleNotificationAction,
    );

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    _messaging.onTokenRefresh.listen((newToken) async {
      final clockNo = currentEmployee?.clockNo;
      if (clockNo != null) {
        await FirebaseFirestore.instance.collection('employees').doc(clockNo).set({
          'fcmToken': newToken,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('FCM token auto-refreshed for $clockNo');
      }
    });

    const MethodChannel jobAlertChannel = MethodChannel('job_alert_channel');

    jobAlertChannel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'handleAlertAction') {
        final String? actionId = call.arguments['actionId'];
        final String? payload = call.arguments['payload'];

        if (actionId != null && payload != null) {
          await handleNotificationAction(NotificationResponse(
            actionId: actionId,
            payload: payload,
            notificationResponseType: NotificationResponseType.selectedNotificationAction,
          ));
        }
      }
    });

    debugPrint('NotificationService initialized successfully');
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final level = message.data['notificationLevel'] ?? 'normal';
    final title = message.data['title'] ?? message.notification?.title ?? 'New Job Notification';
    final body = message.data['body'] ?? message.notification?.body ?? 'You have a new job assignment';

    await _showLocalNotification(title: title, body: body, level: level);
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('App opened from notification');
  }

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
        debugPrint('✅ FCM Token retrieved');
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
        'recipientClockNo': currentEmployee?.clockNo,
      });
    } catch (e) {
      debugPrint('❌ Error sending notification: $e');
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
    } catch (e) {
      debugPrint('❌ Error sending creator notification: $e');
    }
  }

  Future<void> refreshToken() async {
    await getToken();
  }

  Future<void> refreshAndSaveToken(String clockNo) async {
    try {
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await FirebaseFirestore.instance.collection('employees').doc(clockNo).set({
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('FCM token refreshed on startup for $clockNo');
      }
    } catch (e) {
      debugPrint('Error refreshing FCM token on startup: $e');
    }
  }

  Future<void> showOnSiteNotification({
    required String title,
    required String body,
  }) async {
    await _showLocalNotification(title: title, body: body, level: 'normal');
  }

  // ==================== PUBLIC TEST METHODS ====================
  Future<void> testNormalNotification() async {
    await _showLocalNotification(
      title: "TEST - Normal Job Notification",
      body: "This is how normal priority job alerts appear",
      level: 'normal',
    );
  }

  Future<void> testMediumHighNotification() async {
    await _showLocalNotification(
      title: "TEST - Medium/High Priority",
      body: "This is how priority 2 & 3 job alerts appear (persistent style)",
      level: 'medium-high',
    );
  }

  Future<void> testFullLoudNotification() async {
    await _showLocalNotification(
      title: "TEST - URGENT FULL SCREEN",
      body: "This is how priority 4 & 5 full-screen alerts appear (bypasses DND)",
      level: 'full-loud',
    );
  }
}