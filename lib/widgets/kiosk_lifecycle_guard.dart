import 'package:flutter/material.dart';
import '../services/kiosk_mode_service.dart';

/// Re-enters Lock Task Mode whenever the app resumes, in case a force-stop,
/// reboot, or (on non-Device-Owner devices) the screen-pinning "unpin"
/// gesture left the app running without Lock Task Mode active. No-op unless
/// Kiosk Mode has been enabled on this device (see KioskModeScreen).
class KioskLifecycleGuard extends StatefulWidget {
  final Widget child;
  const KioskLifecycleGuard({super.key, required this.child});

  @override
  State<KioskLifecycleGuard> createState() => _KioskLifecycleGuardState();
}

class _KioskLifecycleGuardState extends State<KioskLifecycleGuard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    KioskModeService.instance.reassertIfEnabled();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      KioskModeService.instance.reassertIfEnabled();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
