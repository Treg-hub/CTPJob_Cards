import 'package:cloud_firestore/cloud_firestore.dart';

/// Module config — `work_report_settings/config` (Pulse admin writes).
class WorkReportInclusionRules {
  final bool includeIfAssigned;
  final bool includeIfStartedBy;
  final bool includeIfCompletedBy;
  final bool includeIfCommentedBy;
  final bool includeIfNotedBy;
  final bool requireActivityInPeriod;

  const WorkReportInclusionRules({
    this.includeIfAssigned = true,
    this.includeIfStartedBy = true,
    this.includeIfCompletedBy = true,
    this.includeIfCommentedBy = false,
    this.includeIfNotedBy = false,
    this.requireActivityInPeriod = true,
  });

  factory WorkReportInclusionRules.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const WorkReportInclusionRules();
    return WorkReportInclusionRules(
      includeIfAssigned: data['include_if_assigned'] as bool? ?? true,
      includeIfStartedBy: data['include_if_started_by'] as bool? ?? true,
      includeIfCompletedBy: data['include_if_completed_by'] as bool? ?? true,
      includeIfCommentedBy: data['include_if_commented_by'] as bool? ?? false,
      includeIfNotedBy: data['include_if_noted_by'] as bool? ?? false,
      requireActivityInPeriod:
          data['require_activity_in_period'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'include_if_assigned': includeIfAssigned,
        'include_if_started_by': includeIfStartedBy,
        'include_if_completed_by': includeIfCompletedBy,
        'include_if_commented_by': includeIfCommentedBy,
        'include_if_noted_by': includeIfNotedBy,
        'require_activity_in_period': requireActivityInPeriod,
      };
}

class WorkReportSettings {
  final bool enabled;
  final List<String> enabledClockNos;
  final String timezone;
  final int editablePeriodsBack;
  final double maxHoursPerDay;
  final WorkReportInclusionRules inclusionRules;
  /// When false, job lines with 0h are omitted from PDF/CSV exports.
  final bool includeZeroHourJobs;
  /// Worker + approver signature lines at the foot of the PDF.
  final bool includeSignatureBlock;
  /// Note on PDF when edits occurred after the last generated PDF.
  final bool includePostPdfEditNote;
  /// `calendar_month` (1st–last) or `factory_month` (e.g. 26th–25th).
  final String defaultPeriodMode;
  /// Day of month the factory period opens (only for factory_month). Default 26.
  final int periodStartDay;

  const WorkReportSettings({
    this.enabled = false,
    this.enabledClockNos = const [],
    this.timezone = 'Africa/Johannesburg',
    this.editablePeriodsBack = 1,
    this.maxHoursPerDay = 24,
    this.inclusionRules = const WorkReportInclusionRules(),
    this.includeZeroHourJobs = true,
    this.includeSignatureBlock = true,
    this.includePostPdfEditNote = true,
    this.defaultPeriodMode = 'calendar_month',
    this.periodStartDay = 26,
  });

  static const WorkReportSettings defaults = WorkReportSettings();

  bool get isFactoryPeriodMode =>
      defaultPeriodMode == 'factory_month' && periodStartDay > 1;

  static String normalizeClockNo(dynamic value) {
    if (value == null) return '';
    if (value is int) return value.toString();
    if (value is double && value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString().trim();
  }

  static List<String> _parseClockNoList(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw
          .map(normalizeClockNo)
          .where((c) => c.isNotEmpty)
          .toList();
    }
    final single = normalizeClockNo(raw);
    return single.isEmpty ? const [] : [single];
  }

  factory WorkReportSettings.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final mode = data['default_period_mode'] as String? ?? 'calendar_month';
    return WorkReportSettings(
      enabled: data['enabled'] as bool? ?? false,
      enabledClockNos: _parseClockNoList(data['enabled_clock_nos']),
      timezone: data['timezone'] as String? ?? 'Africa/Johannesburg',
      editablePeriodsBack: data['editable_periods_back'] as int? ?? 1,
      maxHoursPerDay: (data['max_hours_per_day'] as num?)?.toDouble() ?? 24,
      inclusionRules: WorkReportInclusionRules.fromMap(
        data['job_inclusion_rules'] as Map<String, dynamic>?,
      ),
      includeZeroHourJobs: data['include_zero_hour_jobs'] as bool? ?? true,
      includeSignatureBlock: data['include_signature_block'] as bool? ?? true,
      includePostPdfEditNote:
          data['include_post_pdf_edit_note'] as bool? ?? true,
      defaultPeriodMode:
          mode == 'factory_month' ? 'factory_month' : 'calendar_month',
      periodStartDay: (data['period_start_day'] as num?)?.toInt() ?? 26,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'enabled': enabled,
        'enabled_clock_nos': enabledClockNos,
        'timezone': timezone,
        'editable_periods_back': editablePeriodsBack,
        'max_hours_per_day': maxHoursPerDay,
        'job_inclusion_rules': inclusionRules.toFirestore(),
        'include_zero_hour_jobs': includeZeroHourJobs,
        'include_signature_block': includeSignatureBlock,
        'include_post_pdf_edit_note': includePostPdfEditNote,
        'default_period_mode': defaultPeriodMode,
        'period_start_day': periodStartDay,
      };
}