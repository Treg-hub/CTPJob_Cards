import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Locks the device to this app (Android Lock Task Mode) so a dedicated
/// kiosk tablet — e.g. the main-gate Site Security device — can't be
/// flipped over to the home screen, browser, or another app.
///
/// Two tiers, depending on native provisioning (see KioskDeviceAdminReceiver
/// + MainActivity.kt):
///  - **Device Owner enrolled**: full lockdown — no system "unpin" gesture,
///    no home/recents/notifications/power-menu. Only this service calling
///    [exitKioskMode] gets out.
///  - **Not enrolled**: best-effort screen pinning — still pins the app, but
///    a determined user can exit via the standard long-press back+recents
///    gesture. [isDeviceOwner] tells the UI which tier is active so
///    KioskModeScreen can show the right setup guidance.
///
/// Exit-code verification is intentionally **local-only** (salted SHA-256
/// cached in SharedPreferences, per device) rather than server-checked, so
/// unlocking still works if the gate tablet's network is down. See
/// Components/kiosk-lockdown.md for the tradeoff. The alternative escape
/// hatch — an admin's own signed-in identity — is checked by the caller
/// (KioskModeScreen), not here.
class KioskModeService {
  KioskModeService._();
  static final KioskModeService instance = KioskModeService._();

  static const _channel = MethodChannel('ctp/kiosk');
  static const _prefsEnabledKey = 'kiosk_mode_enabled';
  static const _prefsHashKey = 'kiosk_exit_code_hash';
  static const _prefsSaltKey = 'kiosk_exit_code_salt';
  static const _prefsFailCountKey = 'kiosk_exit_fail_count';
  static const _prefsLockUntilKey = 'kiosk_exit_lock_until';

  /// After this many consecutive wrong codes, unlock attempts are locally
  /// locked out for [lockoutDuration] (repeats every further 5 failures).
  static const failuresBeforeLockout = 5;
  static const lockoutDuration = Duration(seconds: 30);

  Future<bool> isDeviceOwner() async {
    try {
      return await _channel.invokeMethod<bool>('isDeviceOwner') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isLockTaskActive() async {
    try {
      return await _channel.invokeMethod<bool>('isLockTaskActive') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isKioskModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsEnabledKey) ?? false;
  }

  Future<bool> hasExitCodeConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsHashKey) != null;
  }

  String _hash(String code, String salt) {
    return sha256.convert(utf8.encode('$salt:$code')).toString();
  }

  String _generateSalt() {
    final rand = Random.secure();
    return List<int>.generate(16, (_) => rand.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Admin-only call site (KioskModeScreen) enforces who may set/rotate this.
  Future<void> setExitCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = _generateSalt();
    await prefs.setString(_prefsSaltKey, salt);
    await prefs.setString(_prefsHashKey, _hash(code, salt));
    await prefs.remove(_prefsFailCountKey);
    await prefs.remove(_prefsLockUntilKey);
  }

  /// Non-null when unlock attempts are currently locked out after too many
  /// consecutive wrong codes. Callers should surface this before prompting.
  Future<Duration?> lockoutRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    final lockUntilMs = prefs.getInt(_prefsLockUntilKey);
    if (lockUntilMs == null) return null;
    final remaining =
        DateTime.fromMillisecondsSinceEpoch(lockUntilMs).difference(DateTime.now());
    return remaining > Duration.zero ? remaining : null;
  }

  Future<bool> verifyExitCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    if (await lockoutRemaining() != null) return false;
    final salt = prefs.getString(_prefsSaltKey);
    final storedHash = prefs.getString(_prefsHashKey);
    if (salt == null || storedHash == null) return false;

    if (_hash(code, salt) == storedHash) {
      await prefs.remove(_prefsFailCountKey);
      await prefs.remove(_prefsLockUntilKey);
      return true;
    }

    final fails = (prefs.getInt(_prefsFailCountKey) ?? 0) + 1;
    await prefs.setInt(_prefsFailCountKey, fails);
    if (fails % failuresBeforeLockout == 0) {
      await prefs.setInt(
        _prefsLockUntilKey,
        DateTime.now().add(lockoutDuration).millisecondsSinceEpoch,
      );
    }
    return false;
  }

  /// Enables kiosk mode: persists the flag and enters Lock Task Mode now.
  /// Returns true if full (Device Owner) lockdown is active, false if only
  /// best-effort screen pinning was available.
  Future<bool> enterKioskMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabledKey, true);
    try {
      return await _channel.invokeMethod<bool>('startKioskMode') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Disables kiosk mode. Callers MUST already have verified admin identity
  /// or the exit code — this performs no check of its own.
  Future<void> exitKioskMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabledKey, false);
    try {
      await _channel.invokeMethod('stopKioskMode');
    } catch (_) {
      // Already unlocked (or never actually entered Lock Task Mode) — fine.
    }
  }

  /// Call on every app launch/resume: if Kiosk Mode is supposed to be on but
  /// Lock Task Mode isn't currently active (force-stop, reboot, or — on a
  /// non-Device-Owner device — the user having exited via the system unpin
  /// gesture), silently re-enter it.
  Future<void> reassertIfEnabled() async {
    if (!await isKioskModeEnabled()) return;
    if (await isLockTaskActive()) return;
    try {
      await _channel.invokeMethod('startKioskMode');
    } catch (_) {
      // Best-effort — surfaced next time KioskModeScreen is opened.
    }
  }
}
