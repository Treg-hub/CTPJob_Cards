import 'dart:async' show unawaited;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:mobile_scanner/mobile_scanner.dart';

/// True when [error] is the plugin's "still initializing" guard.
bool isMobileScannerInitializingError(Object error) {
  return error is MobileScannerException &&
      error.errorCode == MobileScannerErrorCode.controllerInitializing;
}

/// Skip [start] when the camera is already active.
bool shouldSkipMobileScannerStart(MobileScannerController controller) =>
    controller.value.isRunning;

/// Backoff for start retries — 200ms, 400ms, 800ms, … capped at 3.2s.
Duration mobileScannerStartRetryDelay(int attempt) {
  final capped = attempt.clamp(0, 4);
  return Duration(milliseconds: 200 * (1 << capped));
}

/// Poll until [controller] is not mid-start, or [timeout] elapses.
Future<void> waitForMobileScannerIdle(
  MobileScannerController controller, {
  Duration timeout = const Duration(seconds: 8),
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (controller.value.isStarting && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(pollInterval);
  }
}

void logMobileScannerNonFatal(
  Object error,
  StackTrace stack, {
  required String debugName,
  String reason = 'mobile_scanner',
}) {
  debugPrint('MobileScannerLifecycle[$debugName]: $error');
  if (kIsWeb) return;
  unawaited(
    FirebaseCrashlytics.instance.recordError(
      error,
      stack,
      reason: '${reason}_$debugName',
      fatal: false,
    ),
  );
}

/// Dedupes concurrent [start] calls and waits out `controllerInitializing`
/// races on slow OEM camera stacks (e.g. Honor).
class MobileScannerStartGuard {
  Future<void>? _inFlight;

  Future<void> start(
    MobileScannerController controller, {
    required String debugName,
    int maxAttempts = 5,
  }) {
    final existing = _inFlight;
    if (existing != null) return existing;

    final future = _start(
      controller,
      debugName: debugName,
      maxAttempts: maxAttempts,
    );
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<void> _start(
    MobileScannerController controller, {
    required String debugName,
    required int maxAttempts,
  }) async {
    if (shouldSkipMobileScannerStart(controller)) return;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (shouldSkipMobileScannerStart(controller)) return;

      if (controller.value.isStarting) {
        await waitForMobileScannerIdle(controller);
        if (shouldSkipMobileScannerStart(controller)) return;
      }

      try {
        await controller.start();
        return;
      } on MobileScannerException catch (e, st) {
        if (isMobileScannerInitializingError(e)) {
          await waitForMobileScannerIdle(controller);
          if (shouldSkipMobileScannerStart(controller)) return;
          await Future<void>.delayed(mobileScannerStartRetryDelay(attempt));
          continue;
        }
        logMobileScannerNonFatal(
          e,
          st,
          debugName: debugName,
          reason: 'mobile_scanner_start',
        );
        return;
      } catch (e, st) {
        logMobileScannerNonFatal(
          e,
          st,
          debugName: debugName,
          reason: 'mobile_scanner_start',
        );
        await Future<void>.delayed(mobileScannerStartRetryDelay(attempt));
      }
    }
  }
}

/// Best-effort stop — waits for an in-flight start to finish first.
Future<void> safeMobileScannerStop(
  MobileScannerController controller, {
  required String debugName,
}) async {
  try {
    await waitForMobileScannerIdle(
      controller,
      timeout: const Duration(seconds: 4),
    );
    if (controller.value.isRunning) {
      await controller.stop();
    }
  } catch (e, st) {
    logMobileScannerNonFatal(
      e,
      st,
      debugName: debugName,
      reason: 'mobile_scanner_stop',
    );
  }
}