# Web & Platform Compatibility Rules

## Core Principle
This app must remain **functional on Web**, even if some advanced features are disabled on web.

## Mandatory Rules

### 1. Platform Checks (Always Required)
- **Never** initialize mobile-only packages without checking the platform.
- Always use `kIsWeb` from `package:flutter/foundation.dart` for web checks.
- Use `Platform.isAndroid` / `Platform.isIOS` **only** inside `!kIsWeb` blocks.

**Correct Pattern:**
```dart
import 'package:flutter/foundation.dart' show kIsWeb;

if (!kIsWeb) {
  // Mobile-only code here (e.g. background services, geofencing)
}
2. Background Services

flutter_background_service → Only for Android & iOS
workmanager → Only for Android & iOS (currently removed)
Any periodic background task must be wrapped with if (!kIsWeb)

3. Location & Permissions

geolocator background features must be guarded.
permission_handler should still work on web for basic permissions, but some features (like precise location in background) are limited.

4. Firebase & Web

Always use DefaultFirebaseOptions.currentPlatform
Be careful with Firebase plugins that have limited web support (e.g. some Crashlytics features)

5. UI & Assets

Never assume mobile-only widgets or screen sizes
Test on web regularly (flutter run -d chrome)

When to Add Platform Checks
Add !kIsWeb guard when using:

flutter_background_service
workmanager
Background location tracking
Any plugin that throws "supported for Android and iOS only"
Native platform channels

Example of Good Practice
Dart// In main.dart
if (!kIsWeb) {
  await BackgroundGeofenceService.initializeService();
}
Notes for AI Assistants (Cline / Cursor / etc.)

When the user asks to add background features, always ask if web support is needed.
If adding a new package, check if it supports web.
Prefer solutions that work cross-platform when possible.
Update this file when new platform-specific rules are discovered.

Last Updated: April 23, 2026