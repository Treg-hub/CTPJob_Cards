# CTP Job Cards — R8 / ProGuard (release minify)
# Goal: shrink APK without breaking FCM, geofence, scanner, kiosk, or install.
# Library consumer rules from Firebase / Flutter plugins are merged automatically.
# Tighten com.ctp.jobcards keep later only after pilot is stable.

# ── App package (receivers, FGS, FCM service, MainActivity, geofence, kiosk) ──
-keep class com.ctp.jobcards.** { *; }
-keepclassmembers class com.ctp.jobcards.** { *; }

# ── Flutter embedding ────────────────────────────────────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# ── Firebase ─────────────────────────────────────────────────────────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# FCM data messages / RemoteMessage
-keepclassmembers class * extends com.google.firebase.messaging.FirebaseMessagingService {
    public void *;
}

# ── Play Services Location / Geofencing ──────────────────────────────────────
-keep class com.google.android.gms.location.** { *; }
-keep class com.google.android.gms.common.** { *; }

# ── ML Kit / barcode (mobile_scanner) ────────────────────────────────────────
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.libraries.barhopper.** { *; }
-keep class com.google.photos.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.libraries.barhopper.**

# ── WorkManager (workmanager plugin + on-site poll) ──────────────────────────
-keep class androidx.work.** { *; }
-keep class androidx.work.impl.** { *; }
-keepclassmembers class * extends androidx.work.Worker {
    public <init>(android.content.Context,androidx.work.WorkerParameters);
}
-keepclassmembers class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context,androidx.work.WorkerParameters);
}

# ── FileProvider / in-app APK install ────────────────────────────────────────
-keep class androidx.core.content.FileProvider { *; }
-keep class androidx.core.content.ContextCompat { *; }

# ── Device admin / kiosk ─────────────────────────────────────────────────────
-keep class android.app.admin.** { *; }

# ── Enums (plugins + GMS) ────────────────────────────────────────────────────
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# ── Kotlin ───────────────────────────────────────────────────────────────────
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-keepclassmembers class **$WhenMappings { <fields>; }
-keepclassmembers class kotlin.Metadata { public <methods>; }

# ── AndroidX / Material (avoid rare resource/class strip issues) ────────────
-keep class androidx.lifecycle.** { *; }
-keep class com.google.android.material.** { *; }
-dontwarn com.google.android.material.**

# ── Desugar / common noisy warnings ──────────────────────────────────────────
-dontwarn java.lang.invoke.**
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**

# ── Crashlytics (if mapping uploaded later) ──────────────────────────────────
-keepattributes SourceFile,LineNumberTable
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-renamesourcefileattribute SourceFile
