import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/ctp_app_bar.dart';

/// Retired from the mobile shell (Firestore Phase A, 2026-07-09).
///
/// Manager job analytics belong on **CTP Pulse** (`/jobs` + board Job Cards
/// module). This screen remains only as a safe landing if anything still
/// navigates here — it does not open Firestore listeners.
class ManagerDashboardScreen extends StatelessWidget {
  const ManagerDashboardScreen({super.key});

  static const pulseJobsUrl = 'https://ctp-pulse.web.app/jobs';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const CtpAppBar(title: 'Manager Dashboard'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.desktop_windows_outlined,
                    size: 56, color: scheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Moved to CTP Pulse',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Department KPIs, open-job stock, and manager analytics run on '
                  'the factory board web app so the floor app stays light on '
                  'Firestore reads.\n\n'
                  'Open CTP Pulse → Job Cards, or go directly to /jobs on a desk browser.',
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: FilledButton.styleFrom(backgroundColor: kBrandOrange),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
