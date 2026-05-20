import 'dart:io' show Platform;
import 'dart:typed_data' show Int64List;

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show currentEmployee, navigatorKey;
import '../models/job_card.dart';
import '../screens/job_card_detail_screen.dart';

// Channel IDs — must match those declared on the native side (FirebaseMessagingService.kt).
// Each priority maps to one channel:
//   normal (P1-P2)       → basic_notification_channel
//   banner (P3)          → banner_standard_channel
//   medium-high (P4)     → banner_loud_channel
//   full-loud (P5)       → banner_loud_channel in foreground; full-screen activity in background
const String _basicChannel          = 'basic_notification_channel';
const String _standardBannerChannel = 'banner_standard_channel';
const String _loudBannerChannel     = 'banner_loud_channel';

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  // audioplayers_web is not bundled in the web build; audio alerts are Android-only.
  final AudioPlayer? _foregroundSoundPlayer = kIsWeb ? null : AudioPlayer();

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
  // Three channels matching the native side. Foreground notifications are silent
  // at the channel level for P4/P5 — Flutter plays the sound separately at a
  // controlled volume (P4 50%, P5 70%) via _playForegroundSound().
  Future<void> _createNotificationChannels() async {
    if (!Platform.isAndroid) return;

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    // P1-P2: basic — default sound, no DND bypass, no buttons (handled at notification level)
    await androidPlugin?.createNotificationChannel(AndroidNotificationChannel(
      _basicChannel, 'Standard Job Notifications',
      description: 'P1-P2 — basic notifications',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    ));

    // P3: persistent banner — default sound, no DND bypass
    await androidPlugin?.createNotificationChannel(AndroidNotificationChannel(
      _standardBannerChannel, 'Persistent Job Alerts (Standard)',
      description: 'P3 — persistent banner, default sound',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    ));

    // P4 + P5-foreground: persistent banner. The channel itself is SILENT
    // (playSound: false) so we can control volume from Flutter. Background-side
    // (native FirebaseMessagingService) uses its own channel with alarm sound +
    // DND bypass for the same channelId — that's the case when the app is killed.
    await androidPlugin?.createNotificationChannel(AndroidNotificationChannel(
      _loudBannerChannel, 'Persistent Job Alerts (Urgent)',
      description: 'P4/P5 — persistent banner (foreground sound played separately)',
      importance: Importance.high,
      enableVibration: true,
      playSound: false,
      vibrationPattern: Int64List.fromList([0, 800, 300, 800]),
    ));

    debugPrint('All notification channels created successfully');
  }

  // ==================== FOREGROUND SOUND ====================
  // Plays escalation_alert.mp3 at a controlled volume for P4 (50%) and P5 (70%)
  // foreground notifications. Notification channels can't do per-event volume on
  // Android 8+, so we play the sound externally via audioplayers.
  Future<void> _playForegroundSound(double volume) async {
    final player = _foregroundSoundPlayer;
    if (player == null) return;
    try {
      await player.stop();
      await player.setVolume(volume);
      await player.play(AssetSource('sounds/escalation_alert.mp3'));
      debugPrint('🔊 Playing foreground sound at ${(volume * 100).toInt()}% volume');
    } catch (e) {
      debugPrint('Error playing foreground sound: $e');
    }
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
  // Used for FOREGROUND messages only. Background routing happens entirely in
  // native code (FirebaseMessagingService.kt). Maps level → channel and decides
  // whether action buttons appear.
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    required String level,
    String jobCardNumber = "unknown",
  }) async {
    if (kIsWeb) return;

    late final AndroidNotificationDetails androidDetails;
    bool playSoundExternally = false;
    double externalVolume = 0.0;

    // Action buttons for P3-P5. P1-P2 get a basic notification with no buttons.
    final actionButtons = <AndroidNotificationAction>[
      const AndroidNotificationAction('assign_self', 'Assign Self', cancelNotification: false),
      const AndroidNotificationAction('busy',        'Busy',        cancelNotification: false),
      const AndroidNotificationAction('dismiss',     'Dismiss',     cancelNotification: true),
    ];

    switch (level) {
      case 'full-loud':
        // P5 foreground — persistent banner (NOT full-screen), custom sound at 70%
        androidDetails = AndroidNotificationDetails(
          _loudBannerChannel, 'Persistent Job Alerts (Urgent)',
          icon: '@mipmap/ic_launcher',
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
          playSound: false,                       // ← we play sound externally for controlled volume
          vibrationPattern: Int64List.fromList([0, 1200, 400, 1200]),
          ongoing: true,
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.message,
          color: const Color(0xFFFF0000),
          actions: actionButtons,
        );
        playSoundExternally = true;
        externalVolume = 0.7;
        break;

      case 'medium-high':
        // P4 foreground — persistent banner, custom sound at 50%
        androidDetails = AndroidNotificationDetails(
          _loudBannerChannel, 'Persistent Job Alerts (Urgent)',
          icon: '@mipmap/ic_launcher',
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
          playSound: false,                       // ← external sound
          vibrationPattern: Int64List.fromList([0, 800, 300, 800]),
          ongoing: true,
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.message,
          color: const Color(0xFFFF9800),
          actions: actionButtons,
        );
        playSoundExternally = true;
        externalVolume = 0.5;
        break;

      case 'banner':
        // P3 foreground — persistent banner, default Android sound
        androidDetails = AndroidNotificationDetails(
          _standardBannerChannel, 'Persistent Job Alerts (Standard)',
          icon: '@mipmap/ic_launcher',
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
          playSound: true,
          ongoing: true,
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.message,
          color: const Color(0xFFFF9800),
          actions: actionButtons,
        );
        break;

      default:
        // P1-P2 (and operator follow-up, busy responses, etc.) — basic, no buttons
        androidDetails = const AndroidNotificationDetails(
          _basicChannel, 'Standard Job Notifications',
          icon: '@mipmap/ic_launcher',
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
          playSound: true,
          autoCancel: true,
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.message,
          color: Color(0xFF2563A0),
        );
    }

    if (playSoundExternally) {
      // ignore: discarded_futures
      _playForegroundSound(externalVolume);
    }

    await _localNotifications.show(
      id: int.tryParse(jobCardNumber) ?? (DateTime.now().millisecondsSinceEpoch % 2147483647),
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
      } else if (call.method == 'navigateToJobDetail') {
        final String? jobCardNumber = call.arguments['jobCardNumber'];
        if (jobCardNumber != null) {
          await _navigateToJobDetail(jobCardNumber);
        }
      }
    });

    // Foreground tap on a notification body (no action button) — same as tap-to-view
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    debugPrint('NotificationService initialized successfully');
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final level = message.data['notificationLevel'] ?? 'normal';
    final title = message.data['title'] ?? message.notification?.title ?? 'New Job Notification';
    final body = message.data['body'] ?? message.notification?.body ?? 'You have a new job assignment';
    final jobCardNumber = message.data['jobCardNumber'] ?? 'unknown';

    await _showLocalNotification(title: title, body: body, level: level, jobCardNumber: jobCardNumber);
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    final jobCardNumber = message.data['jobCardNumber'];
    if (jobCardNumber != null) {
      // ignore: discarded_futures
      _navigateToJobDetail(jobCardNumber);
    }
  }

  // ==================== NAVIGATE TO JOB DETAIL ====================
  // Called from the native MethodChannel (after Assign Self success or notification
  // tap), or after a foreground notification tap. Uses the global navigator key
  // so it works no matter which screen is currently on top.
  Future<void> _navigateToJobDetail(String jobCardNumber) async {
    try {
      final int? jobNum = int.tryParse(jobCardNumber);
      if (jobNum == null) {
        debugPrint('navigateToJobDetail: invalid jobCardNumber "$jobCardNumber"');
        return;
      }

      final query = await FirebaseFirestore.instance
          .collection('job_cards')
          .where('jobCardNumber', isEqualTo: jobNum)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        debugPrint('navigateToJobDetail: job #$jobCardNumber not found');
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(content: Text('Job not found'), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      final jobCard = JobCard.fromFirestore(query.docs.first);
      final navigator = navigatorKey.currentState;
      if (navigator == null) {
        debugPrint('navigateToJobDetail: navigator not ready, will retry on app start');
        return;
      }

      // Clear any stale pending number — we're acting on it now.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pendingJobCardNumber');

      navigator.push(MaterialPageRoute(
        builder: (_) => JobCardDetailScreen(jobCard: jobCard),
      ));
    } catch (e) {
      debugPrint('navigateToJobDetail error: $e');
    }
  }

  // Called on app start to handle the cold-start case: user tapped a notification
  // while the app was killed, the native side stored the jobCardNumber in
  // SharedPreferences, and now we route to the detail screen.
  Future<void> checkPendingJobNavigation() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString('pendingJobCardNumber');
    if (pending != null && pending.isNotEmpty) {
      debugPrint('checkPendingJobNavigation: found pending job #$pending');
      await _navigateToJobDetail(pending);
    }
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