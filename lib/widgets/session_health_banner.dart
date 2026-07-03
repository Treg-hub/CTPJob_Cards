import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/login_screen.dart';
import '../services/resilient_stream.dart';

enum _SessionIssue { expired, accountMissing }

/// Home banner when the saved session can no longer read data:
///   • **expired** — SharedPreferences says logged-in but the Firebase Auth
///     session is gone (signed out / revoked / disabled). Every Firestore
///     read fails silently in this state; without the banner it just looks
///     like an empty app.
///   • **accountMissing** — the employee doc was deleted server-side
///     (flagged by HomeScreen via [flagAccountMissing]).
///
/// Recovery is a "Sign in" button — it deliberately does NOT clear
/// SharedPreferences or the Hive sync_queue (queued offline work replays
/// after re-auth), unlike the full logout in Settings. Never auto-navigates
/// (kiosk devices must not have screens pushed spontaneously mid-shift).
///
/// Startup cost: none — everything subscribes post-first-frame, and the only
/// network call (token refresh probe) fires on resume (throttled ≥1 h) or
/// when the resilient stream layer flags repeated permission-denied.
class SessionHealthBanner extends StatefulWidget {
  const SessionHealthBanner({super.key});

  /// Set by HomeScreen when the employee doc is server-confirmed absent.
  static final ValueNotifier<bool> accountMissing = ValueNotifier(false);

  static void flagAccountMissing() => accountMissing.value = true;

  @override
  State<SessionHealthBanner> createState() => _SessionHealthBannerState();
}

class _SessionHealthBannerState extends State<SessionHealthBanner>
    with WidgetsBindingObserver {
  _SessionIssue? _issue;
  bool _sawFirstAuthEvent = false;
  bool _graceElapsed = false;
  DateTime? _lastRevocationProbe;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<void>? _suspectSub;
  Timer? _graceTimer;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    WidgetsBinding.instance.addObserver(this);
    SessionHealthBanner.accountMissing.addListener(_onAccountMissingChanged);
    // Everything below starts after the first frame — no startup cost, and
    // FirebaseAuth gets time to restore the session from disk before we judge.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Grace period: a null currentUser during cold-start restoration must
      // not flash the banner. The FIRST authStateChanges event is the
      // disk-restored user (or a real null); the grace covers a slow restore.
      _graceTimer = Timer(const Duration(seconds: 3), () {
        _graceElapsed = true;
        _evaluate(FirebaseAuth.instance.currentUser);
      });
      _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
        _sawFirstAuthEvent = true;
        _evaluate(user);
      });
      // The resilient stream layer pings this when repeated permission-denied
      // failures suggest the session itself is dead (claims refresh didn't fix
      // it) — probe the token immediately rather than waiting for a resume.
      _suspectSub = RetryTriggers.instance.authSuspectEvents
          .listen((_) => _probeRevocation(force: true));
    });
  }

  @override
  void dispose() {
    if (!kIsWeb) WidgetsBinding.instance.removeObserver(this);
    SessionHealthBanner.accountMissing.removeListener(_onAccountMissingChanged);
    _authSub?.cancel();
    _suspectSub?.cancel();
    _graceTimer?.cancel();
    super.dispose();
  }

  void _onAccountMissingChanged() {
    if (!mounted) return;
    setState(() {
      if (SessionHealthBanner.accountMissing.value) {
        _issue = _SessionIssue.accountMissing;
      } else if (_issue == _SessionIssue.accountMissing) {
        _issue = null;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _probeRevocation();
  }

  Future<void> _evaluate(User? user) async {
    if (!mounted) return;
    if (user != null) {
      // Signed in (or re-signed-in) — the expired issue, if any, is over.
      if (_issue == _SessionIssue.expired) setState(() => _issue = null);
      return;
    }
    if (!_sawFirstAuthEvent || !_graceElapsed) return;
    final prefs = await SharedPreferences.getInstance();
    final looksLoggedIn = prefs.getString('loggedInClockNo') != null;
    if (!mounted) return;
    if (looksLoggedIn && _issue == null) {
      debugPrint('⚠️ SessionHealthBanner: auth session gone, prefs logged-in');
      setState(() => _issue = _SessionIssue.expired);
    }
  }

  /// A locally-cached auth object can outlive a console disable/delete —
  /// force a token refresh to find out. Throttled; never runs at startup.
  Future<void> _probeRevocation({bool force = false}) async {
    if (kIsWeb || _issue != null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final now = DateTime.now();
    if (!force &&
        _lastRevocationProbe != null &&
        now.difference(_lastRevocationProbe!) < const Duration(hours: 1)) {
      return;
    }
    _lastRevocationProbe = now;
    try {
      await user.getIdToken(true);
    } on FirebaseAuthException catch (e) {
      if (const {'user-disabled', 'user-not-found', 'user-token-expired'}
          .contains(e.code)) {
        debugPrint('⚠️ SessionHealthBanner: session revoked (${e.code})');
        if (mounted) setState(() => _issue = _SessionIssue.expired);
      }
    } catch (_) {
      // Offline/transient — not evidence of revocation.
    }
  }

  void _signInAgain() {
    // Reset the account-missing flag — if the profile is still gone, the
    // employee stream re-flags it after the next sign-in.
    SessionHealthBanner.accountMissing.value = false;
    // Unlike Settings → logout, prefs / realEmployee / the Hive sync_queue
    // are left intact: the normal login flow rewrites prefs, and queued
    // offline work replays once re-authenticated.
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final issue = _issue;
    if (kIsWeb || issue == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF3A1414) : const Color(0xFFFDECEA);
    final fg = isDark ? const Color(0xFFFFB4A9) : const Color(0xFFB3261E);

    final (title, subtitle, buttonLabel) = switch (issue) {
      _SessionIssue.expired => (
          'Session expired',
          'Sign in again to reload your data. Unsent work is kept and will sync after you sign in.',
          'Sign in',
        ),
      _SessionIssue.accountMissing => (
          'Your account is no longer active',
          'Your employee profile was removed. Contact your administrator if this is unexpected.',
          'Sign in',
        ),
    };

    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.lock_clock, color: fg, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                  Text(subtitle,
                      style: TextStyle(
                          color: fg.withValues(alpha: 0.85), fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _signInAgain,
              style: FilledButton.styleFrom(
                backgroundColor: fg,
                foregroundColor: bg,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(buttonLabel,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
