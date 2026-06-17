// web_presence_service.dart
//
// Web-only presence guard. Managers who leave the web app open on a PC were
// staying "on site" forever; this marks them OFF-site after 60 minutes of no
// activity, or as soon as the tab is hidden/closed. It NEVER sets on-site —
// browser geolocation is too unreliable, so on-site is mobile-geofence-only.
//
// Pure Flutter (no JS interop): a Listener resets the idle timer on pointer
// activity, and Flutter's lifecycle hidden/paused states (web maps these from
// the browser visibilitychange/pagehide events) catch tab hide/close. On mobile
// the widget is a transparent passthrough.

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firestore_service.dart';

class WebPresenceGuard extends StatefulWidget {
  final Widget child;
  const WebPresenceGuard({super.key, required this.child});

  @override
  State<WebPresenceGuard> createState() => _WebPresenceGuardState();
}

class _WebPresenceGuardState extends State<WebPresenceGuard>
    with WidgetsBindingObserver {
  // 60 min of no activity → off-site (confirmed product decision).
  static const Duration _idleTimeout = Duration(minutes: 60);

  // Lazy: constructing FirestoreService touches FirebaseFirestore.instance, so
  // never build it on non-web (the guard is a passthrough there) or before
  // Firebase is initialised — only when an actual web off-site write happens.
  late final FirestoreService _firestore = FirestoreService();
  Timer? _idleTimer;
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WidgetsBinding.instance.addObserver(this);
      _resetIdleTimer();
    }
  }

  @override
  void dispose() {
    if (kIsWeb) WidgetsBinding.instance.removeObserver(this);
    _idleTimer?.cancel();
    super.dispose();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, () => _markOffSite('web_inactivity'));
  }

  void _onActivity([PointerEvent? _]) => _resetIdleTimer();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb) return;
    // Tab hidden / minimised / closed → leave the site immediately.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _markOffSite('web_hidden');
    } else if (state == AppLifecycleState.resumed) {
      _resetIdleTimer();
    }
  }

  Future<void> _markOffSite(String source) async {
    if (_writing) return;
    _writing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final clockNo = prefs.getString('loggedInClockNo');
      if (clockNo == null) return;
      final emp = await _firestore.getEmployee(clockNo);
      // Only flip a real transition (on-site → off-site); never set on-site.
      if (emp == null || emp.isOnSite != true) return;
      await _firestore.updateMyPresence(isOnSite: false, source: source);
      debugPrint('🌐 Web presence: marked off-site via $source');
    } catch (e) {
      debugPrint('Web presence off-site write failed (non-fatal): $e');
    } finally {
      _writing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onActivity,
      onPointerMove: _onActivity,
      onPointerHover: _onActivity,
      onPointerSignal: _onActivity,
      child: widget.child,
    );
  }
}
