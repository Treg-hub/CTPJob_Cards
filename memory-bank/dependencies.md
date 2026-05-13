# CTP Job Cards — Dependencies Reference

**Purpose**: Single source of truth for correct usage of every dependency in `pubspec.yaml`.  
**Rule**: The agent **MUST** read this file at the start of every task involving any of these packages.  
**Last Updated**: 2026-05-13 (aligned with pubspec.yaml version 1.1.1+5)  
**Maintenance**: Update this file whenever any dependency version changes in `pubspec.yaml`.

---

## 1. State Management — flutter_riverpod ^2.5.3

**Correct Pattern (Riverpod 2.x Notifier)**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

class JobCardNotifier extends Notifier<JobCardState> {
  @override
  JobCardState build() => JobCardState.initial();

  Future<void> loadJobCards() async { ... }
}

final jobCardProvider = NotifierProvider<JobCardNotifier, JobCardState>(
  () => JobCardNotifier(),
);
```

**Common Mistake to Avoid**: Do not use the old `StateNotifier` or `ChangeNotifier` patterns from Riverpod 1.x.

---

## 2. Firebase Suite

### firebase_core ^3.6.0 + cloud_firestore ^5.5.0 + firebase_auth ^5.3.1

**Initialization** (in `main.dart`):
```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);
```

### firebase_messaging ^15.1.3 + cloud_functions ^5.2.0

**Background Handler** (must be top-level):
```dart
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // handle message
}
```

**Correct Setup** (in `main.dart`):
```dart
FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

FirebaseMessaging.onMessage.listen((RemoteMessage message) {
  // foreground handling
});
```

**Get Token**:
```dart
final fcmToken = await FirebaseMessaging.instance.getToken();
```

**Custom Token Auth** (your existing pattern):
Use Cloud Function `createCustomToken` → `FirebaseAuth.instance.signInWithCustomToken(token)`.

### firebase_storage ^12.3.0 + firebase_crashlytics ^4.2.0 + firebase_remote_config ^5.4.0

Standard usage — no special parameters changed in these versions.

---

## 3. Location & Background (Critical — Most Error-Prone)

**Packages**: `geolocator: ^13.0.1`, `permission_handler: ^11.3.1`, `workmanager: ^0.9.0+3`, `android_intent_plus: ^5.0.2`

### Required Android Permissions
Add these **before** the `<application>` tag in `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
```

### Correct Safe Location Fetch (v13+)

```dart
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

Future<Position?> getCurrentPositionSafe() async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return null; // or show dialog
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.deniedForever ||
      permission == LocationPermission.denied) {
    return null;
  }

  return await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
    timeLimit: const Duration(seconds: 15),
  );
}
```

**Common Mistakes to Avoid**:
- Calling `getCurrentPosition` without checking `isLocationServiceEnabled()`
- Using deprecated `forceAndroidLocationManager`
- Missing `FOREGROUND_SERVICE_LOCATION` on Android 14+

### Workmanager Registration (for background geofencing fallback)

```dart
import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // your background location check here
    return Future.value(true);
  });
}

void registerWorkmanager() {
  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  Workmanager().registerPeriodicTask(
    "location-check",
    "locationCheckTask",
    frequency: const Duration(minutes: 15),
  );
}
```

---

## 4. Notifications — flutter_local_notifications ^17.2.3

**Correct Full-Screen Intent + Alarm Setup** (used for P5 priority jobs):

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initLocalNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Request full-screen intent permission (Android 14+)
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestFullScreenIntentPermission();
}
```

**High-Priority Alarm Channel** (create once):

```dart
const AndroidNotificationChannel alarmChannel = AndroidNotificationChannel(
  'alarm_channel',
  'Critical Alarms',
  description: 'Full-screen alarm for P5 jobs',
  importance: Importance.max,
  sound: RawResourceAndroidNotificationSound('escalation_alert'),
  enableVibration: true,
  playSound: true,
);

await flutterLocalNotificationsPlugin
    .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
    ?.createNotificationChannel(alarmChannel);
```

**Show Full-Screen Alarm**:
```dart
await flutterLocalNotificationsPlugin.show(
  0,
  'Critical Job Alert',
  'P5 job requires immediate attention',
  NotificationDetails(
    android: AndroidNotificationDetails(
      'alarm_channel',
      'Critical Alarms',
      fullScreenIntent: true,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
    ),
  ),
);
```

---

## 5. Offline & Local Storage

### hive ^2.2.3 + hive_generator ^2.0.1 + build_runner ^2.4.13

**Model Example**:
```dart
import 'package:hive/hive.dart';

part 'job_card.g.dart';

@HiveType(typeId: 1)
class JobCard extends HiveObject {
  @HiveField(0)
  late String id;

  @HiveField(1)
  late String description;
}
```

**Generate**:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

**Open Box**:
```dart
await Hive.openBox<JobCard>('jobCards');
```

---

## 6. UI, Charts, PDF, Media & Maps

- `fl_chart: ^0.68.0` — Use `LineChart`, `BarChart`, `PieChart` with `FlSpot` and `BarChartGroupData`.
- `pdf: ^3.11.1` + `share_plus: ^10.1.0` — Standard `pw.Document` + `Printing.sharePdf`.
- `cached_network_image: ^3.4.1` — Use with `CachedNetworkImage` widget (already in use).
- `google_maps_flutter: ^2.17.0` — `GoogleMap` widget + `Marker` + `CameraPosition`.
- `image_picker: ^1.1.2` + `flutter_image_compress: ^2.3.0` — Use `ImagePicker().pickImage` then compress to 1024px / 70% quality (your current pattern).
- `file_picker: ^8.1.2` + `csv: ^6.0.0` — For bulk employee import/export.

---

## 7. Utilities

- `uuid: ^4.5.0` → `const Uuid().v4()`
- `intl: ^0.19.0` → `DateFormat('yyyy-MM-dd HH:mm')`
- `url_launcher: ^6.3.0` → `launchUrl(Uri.parse(...))`
- `package_info_plus: ^8.0.2` → `PackageInfo.fromPlatform()`
- `torch_light: ^1.1.0` → `TorchLight.enableTorch()` / `disableTorch()`

---

## 8. General Rules for All Dependencies

1. Always check the **exact version** in `pubspec.yaml` before suggesting code.
2. Prefer the patterns already used in `lib/` (Riverpod Notifiers, FirestoreService, NotificationService, etc.).
3. When in doubt, read the official pub.dev page for that exact version.
4. Never use deprecated methods (e.g., old `withOpacity`, old Workmanager registration).

---

**End of Dependencies Reference**

This file ensures consistent, correct, and future-proof usage across the entire CTP Job Cards project.