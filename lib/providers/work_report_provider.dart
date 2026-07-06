import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/work_report_settings.dart';
import '../services/work_report_service.dart';

final workReportServiceProvider = Provider<WorkReportService>((ref) {
  return WorkReportService();
});

final workReportSettingsProvider = StreamProvider<WorkReportSettings>((ref) {
  return ref.watch(workReportServiceProvider).watchSettings();
});

/// Subject worker clock number for admin "view as" mode.
final workReportSubjectClockProvider = StateProvider<String?>((ref) => null);

final workReportPeriodKeyProvider = StateProvider<String>((ref) {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
});