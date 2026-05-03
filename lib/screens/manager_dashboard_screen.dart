import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../models/job_card.dart';
import '../services/connectivity_service.dart';
import '../services/firestore_service.dart';
import '../main.dart' show currentEmployee;
import '../widgets/skeleton_loader.dart';
import '../widgets/sync_indicator.dart';
import '../theme/app_theme.dart';
import 'copper_dashboard_screen.dart';
import 'job_card_detail_screen.dart';

class ManagerDashboardScreen extends ConsumerStatefulWidget {
  const ManagerDashboardScreen({super.key});

  @override
  ConsumerState<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends ConsumerState<ManagerDashboardScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final ConnectivityService _connectivityService = ConnectivityService();

  int _totalJobs = 0;
  int _openJobsCount = 0;
  int _completed7Days = 0;
  int _completed30Days = 0;
  double _completionRate = 0.0;
  Duration? _averageCompletionTime;
  Duration? _avgResponseTime;
  int _pendingAssignments = 0;
  int _agedOpen7d = 0;
  int _agedOpen30d = 0;
  int _createdThisMonth = 0;
  int _closedThisMonth = 0;

  final Map<DateTime, int> _createdDaily = {};
  final Map<DateTime, int> _closedDaily = {};
  final Map<String, int> _createdByDept = {};
  final Map<String, int> _closedByDept = {};
  final Map<DateTime, Map<String, int>> _outstandingByDeptDaily = {};
  final Map<DateTime, Map<String, int>> _outstandingByAreaDaily = {};

  Set<String> _selectedDepts = {};
  Set<String> _selectedAreas = {};
  Set<String> _selectedPieDepts = {};

  bool _isLoading = true;

  String? selectedDept;
  DateTime? selectedMonth;
  List<String>? _departments;

  List<JobCard> _filteredJobsCache = [];
  DateTime? _lastUpdated;

  bool get _isMobile => MediaQuery.of(context).size.width < 600;
  bool get _isTablet => MediaQuery.of(context).size.width >= 600 && MediaQuery.of(context).size.width < 1200;
  bool get _isDesktop => MediaQuery.of(context).size.width >= 1200;

  int get _metricsCrossAxisCount => _isDesktop ? 6 : (_isTablet ? 4 : 2);
  double get _screenPadding => _isDesktop ? 32 : (_isTablet ? 24 : 16);
  double get _sectionSpacing => _isDesktop ? 32 : (_isTablet ? 24 : 16);

  late final CollectionReference<JobCard> _jobCardsCollection;

  @override
  void initState() {
    super.initState();
    _jobCardsCollection = FirebaseFirestore.instance.collection('job_cards').withConverter<JobCard>(
      fromFirestore: (snapshot, _) => JobCard.fromFirestore(snapshot),
      toFirestore: (job, _) => job.toFirestore(),
    );
    _loadDashboardData();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    try {
      final snapshot = await _jobCardsCollection.get();
      final depts = snapshot.docs.map((doc) => doc.data().department).where((d) => d.isNotEmpty).toSet();
      _departments = depts.toList()..sort();
      if (mounted) setState(() {});
    } catch (e) {}
  }

  Future<void> _loadDashboardData([String? dept, DateTime? month]) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      Query<JobCard> query = _jobCardsCollection;
      if (dept != null && dept.isNotEmpty) query = query.where('department', isEqualTo: dept);

      if (month != null) {
        final start = DateTime(month.year, month.month, 1);
        final end = DateTime(month.year, month.month + 1, 1).subtract(const Duration(days: 1));
        query = query
            .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end));
      }

      final snapshot = await query.get();
      final jobs = snapshot.docs.map((doc) => doc.data()).toList();

      _filteredJobsCache = jobs;

      // Compute analytics data
      _createdDaily.clear();
      _closedDaily.clear();
      _createdByDept.clear();
      _closedByDept.clear();
      _createdThisMonth = 0;
      _closedThisMonth = 0;

      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      final startOfMonth = DateTime(now.year, now.month, 1);

      for (var job in jobs) {
        if (job.createdAt != null) {
          final date = job.createdAt!.toLocal();
          if (date.isAfter(thirtyDaysAgo)) {
            final day = DateTime(date.year, date.month, date.day);
            _createdDaily[day] = (_createdDaily[day] ?? 0) + 1;
          }
          if (date.isAfter(startOfMonth)) {
            _createdThisMonth++;
          }
          final dept = job.department ?? 'Other';
          _createdByDept[dept] = (_createdByDept[dept] ?? 0) + 1;
        }
        if (job.completedAt != null && job.status == JobStatus.closed) {
          final date = job.completedAt!.toLocal();
          if (date.isAfter(thirtyDaysAgo)) {
            final day = DateTime(date.year, date.month, date.day);
            _closedDaily[day] = (_closedDaily[day] ?? 0) + 1;
          }
          if (date.isAfter(startOfMonth)) {
            _closedThisMonth++;
          }
          final dept = job.department ?? 'Other';
          _closedByDept[dept] = (_closedByDept[dept] ?? 0) + 1;
        }
      }

      _totalJobs = jobs.length;
      _openJobsCount = jobs.where((j) => j.status == JobStatus.open).length;

      _completed7Days = jobs.where((j) => j.status == JobStatus.closed && j.completedAt != null && j.completedAt!.isAfter(now.subtract(const Duration(days: 7)))).length;
      _completed30Days = jobs.where((j) => j.status == JobStatus.closed && j.completedAt != null && j.completedAt!.isAfter(now.subtract(const Duration(days: 30)))).length;

      final completedInPeriod = jobs.where((j) => j.status == JobStatus.closed).length;
      _completionRate = _totalJobs > 0 ? (completedInPeriod / _totalJobs * 100) : 0.0;

      final completedJobs = jobs.where((j) => j.status == JobStatus.closed && j.createdAt != null && j.completedAt != null).toList();
      if (completedJobs.isNotEmpty) {
        var totalDuration = Duration.zero;
        for (var j in completedJobs) {
          totalDuration += j.completedAt!.difference(j.createdAt!);
        }
        _averageCompletionTime = totalDuration ~/ completedJobs.length;
      } else {
        _averageCompletionTime = null;
      }

      final responseJobs = jobs.where((j) => j.createdAt != null && j.assignedAt != null).toList();
      if (responseJobs.isNotEmpty) {
        var totalResponse = Duration.zero;
        for (var j in responseJobs) {
          totalResponse += j.assignedAt!.difference(j.createdAt!);
        }
        _avgResponseTime = totalResponse ~/ responseJobs.length;
      } else {
        _avgResponseTime = null;
      }

      _pendingAssignments = jobs.where((j) => j.status == JobStatus.open && (j.assignedClockNos == null || j.assignedClockNos!.isEmpty)).length;

      final openJobs = jobs.where((j) => j.status == JobStatus.open && j.createdAt != null).toList();
      _agedOpen7d = openJobs.where((j) => j.createdAt!.isBefore(now.subtract(const Duration(days: 7)))).length;
      _agedOpen30d = openJobs.where((j) => j.createdAt!.isBefore(now.subtract(const Duration(days: 30)))).length;

      // Compute outstanding by dept daily
      _outstandingByDeptDaily.clear();
      for (int i = 29; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        final day = DateTime(date.year, date.month, date.day);
        final outstanding = <String, int>{};
        for (var job in jobs) {
          if (job.createdAt != null && job.createdAt!.toLocal().isBefore(day.add(const Duration(days: 1))) &&
              (job.completedAt == null || job.completedAt!.toLocal().isAfter(day))) {
            final dept = job.department ?? 'Other';
            outstanding[dept] = (outstanding[dept] ?? 0) + 1;
          }
        }
        _outstandingByDeptDaily[day] = outstanding;
      }

      // Compute outstanding by area daily
      _outstandingByAreaDaily.clear();
      for (int i = 29; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        final day = DateTime(date.year, date.month, date.day);
        final outstanding = <String, int>{};
        for (var job in jobs) {
          if (job.createdAt != null && job.createdAt!.toLocal().isBefore(day.add(const Duration(days: 1))) &&
              (job.completedAt == null || job.completedAt!.toLocal().isAfter(day))) {
            final area = job.area ?? 'Other';
            outstanding[area] = (outstanding[area] ?? 0) + 1;
          }
        }
        _outstandingByAreaDaily[day] = outstanding;
      }

      // Initialize selected sets
      final allDepts = _outstandingByDeptDaily.values.expand((m) => m.keys).toSet().toList()..sort();
      final allAreas = _outstandingByAreaDaily.values.expand((m) => m.keys).toSet().toList()..sort();
      final allPieDepts = _filteredJobsCache.map((j) => j.department ?? 'Other').toSet().toList()..sort();
      _selectedDepts = allDepts.toSet();
      _selectedAreas = allAreas.toSet();
      _selectedPieDepts = allPieDepts.toSet();

      _lastUpdated = DateTime.now();
    } catch (e) {
      debugPrint('Error loading dashboard: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getLastUpdatedText() {
    if (_lastUpdated == null) return 'Never';
    final diff = DateTime.now().difference(_lastUpdated!);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  Color _getPriorityColor(String priority) {
    final num = int.tryParse(priority.substring(1)) ?? 0;
    switch (num) {
      case 1: return Theme.of(context).appColors.priority1;
      case 2: return Theme.of(context).appColors.priority2;
      case 3: return Theme.of(context).appColors.priority3;
      case 4: return Theme.of(context).appColors.priority4;
      case 5: return Theme.of(context).appColors.priority5;
      default: return Colors.grey;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return Theme.of(context).appColors.statusOpen;
      case 'in progress':
        return Theme.of(context).appColors.statusInProgress;
      case 'completed':
        return Theme.of(context).appColors.statusCompleted;
      case 'cancelled':
        return Theme.of(context).appColors.statusCancelled;
      default:
        return Colors.grey;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _getLastCommentPreview(String comments) {
    final parts = comments.split('\n\n').where((c) => c.trim().isNotEmpty).toList();
    if (parts.isEmpty) return '';
    final lastComment = parts.last;
    final lines = lastComment.split('\n');
    return lines.length > 1 ? lines[1].trim() : lastComment.trim();
  }

  Widget _buildJobCardWidget(JobCard job) {
    return Card(
      elevation: 6,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => JobCardDetailScreen(jobCard: job)),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'P${job.priority}',
                      style: TextStyle(
                        color: _getPriorityColor('P${job.priority}'),
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                    TextSpan(
                      text: ' | ${job.department ?? 'N/A'} > ${job.area ?? 'N/A'} > ${job.machine ?? 'N/A'} > ${job.part ?? 'N/A'} | ${job.operator ?? 'Unknown'}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11.5,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (job.jobCardNumber != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 204),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'JC #${job.jobCardNumber}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      job.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.normal,
                        fontSize: 15,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
              if (job.comments.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _getLastCommentPreview(job.comments),
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade300, fontStyle: FontStyle.italic),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (job.notes.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  job.notes.split('\n').last.trim(),
                  style: const TextStyle(fontSize: 12, color: Colors.white70, fontStyle: FontStyle.italic),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                              color: _getStatusColor(job.status.name).withValues(alpha: 128),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      job.status.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                              color: Colors.blueGrey.withValues(alpha: 64),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      job.type.displayName,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      job.assignedNames?.join(', ') ?? 'Unassigned',
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    job.lastUpdatedAt != null ? _formatDateTime(job.lastUpdatedAt!) : '—',
                    style: const TextStyle(color: Color(0xFFFF8C42), fontSize: 12),
                  ),
                  const SizedBox(width: 12),
                  Row(
                    children: [
                      if (job.comments.isNotEmpty) Icon(Icons.comment_outlined, size: 16, color: Colors.blue[400]),
                      if (job.notes.isNotEmpty) Icon(Icons.build_outlined, size: 16, color: Colors.orange[400]),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMonthPicker() {
    showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    ).then((date) {
      if (date != null) {
        setState(() => selectedMonth = date);
        _loadDashboardData(selectedDept, selectedMonth);
      }
    });
  }

  void _showExportOptions() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PDF Export coming soon')),
    );
  }

  Widget _buildMetricsSection() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _metricsCrossAxisCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.8,
      ),
      itemCount: 11,
      itemBuilder: (context, index) {
        final data = [
          {'title': 'Total Jobs', 'value': _totalJobs.toString(), 'color': Colors.blue},
          {'title': 'Open Jobs', 'value': _openJobsCount.toString(), 'color': Colors.orange},
          {'title': 'Completed (7d)', 'value': _completed7Days.toString(), 'color': Colors.green},
          {'title': 'Completion %', 'value': '${_completionRate.toStringAsFixed(0)}%', 'color': Colors.purple},
          {'title': 'Pending Assign', 'value': _pendingAssignments.toString(), 'color': Colors.red},
          {'title': 'Aged >7d', 'value': _agedOpen7d.toString(), 'color': Colors.redAccent},
          {'title': 'Created (Month)', 'value': _createdThisMonth.toString(), 'color': Colors.blueAccent},
          {'title': 'Closed (Month)', 'value': _closedThisMonth.toString(), 'color': Colors.greenAccent},
          {'title': 'Avg Completion Time', 'value': _averageCompletionTime != null ? '${_averageCompletionTime!.inDays}d ${_averageCompletionTime!.inHours % 24}h' : 'N/A', 'color': Colors.teal},
          {'title': 'Avg Response Time', 'value': _avgResponseTime != null ? '${_avgResponseTime!.inDays}d ${_avgResponseTime!.inHours % 24}h' : 'N/A', 'color': Colors.indigo},
          {'title': 'Aged >30d', 'value': _agedOpen30d.toString(), 'color': Colors.deepOrange},
        ][index];

        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(data['title'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Text(data['value'] as String, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: data['color'] as Color)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChartsSection() {
    final now = DateTime.now();
    final createdSpots = <FlSpot>[];
    final closedSpots = <FlSpot>[];
    for (int i = 29; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final day = DateTime(date.year, date.month, date.day);
      createdSpots.add(FlSpot((29 - i).toDouble(), (_createdDaily[day] ?? 0).toDouble()));
      closedSpots.add(FlSpot((29 - i).toDouble(), (_closedDaily[day] ?? 0).toDouble()));
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Created vs Closed Trend (Last 30 days)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: true),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value % 7 == 0) {
                            final date = now.subtract(Duration(days: 29 - value.toInt()));
                            return Text('${date.day}/${date.month}', style: const TextStyle(fontSize: 10));
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true)),
                  ),
                  borderData: FlBorderData(show: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: createdSpots,
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 3,
                      belowBarData: BarAreaData(show: false),
                      dotData: const FlDotData(show: false),
                    ),
                    LineChartBarData(
                      spots: closedSpots,
                      isCurved: true,
                      color: Colors.green,
                      barWidth: 3,
                      belowBarData: BarAreaData(show: false),
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Chip(
                  avatar: const CircleAvatar(backgroundColor: Colors.blue, radius: 6),
                  label: const Text('Created'),
                  backgroundColor: Colors.blue.withValues(alpha: 51),
                ),
                const SizedBox(width: 8),
                Chip(
                  avatar: const CircleAvatar(backgroundColor: Colors.green, radius: 6),
                  label: const Text('Closed'),
                  backgroundColor: Colors.green.withValues(alpha: 51),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDeptChart(),
            const SizedBox(height: 16),
            _buildAreaChart(),
            const SizedBox(height: 16),
            _buildPieChart(),
          ],
        ),
      ),
    );
  }

  Widget _buildDeptChart() {
    final now = DateTime.now();
    final allDepts = _outstandingByDeptDaily.values.expand((m) => m.keys).toSet().toList()..sort();
    const List<Color> deptColors = [Colors.green, Colors.blue, Colors.brown, Colors.red, Colors.orange, Colors.purple, Colors.teal, Colors.pink, Colors.indigo, Colors.amber, Colors.cyan, Colors.lime];

    final lineBarsData = <LineChartBarData>[];
    for (int i = 0; i < allDepts.length; i++) {
      final dept = allDepts[i];
      if (!_selectedDepts.contains(dept)) continue;
      final spots = <FlSpot>[];
      for (int j = 29; j >= 0; j--) {
        final date = now.subtract(Duration(days: j));
        final day = DateTime(date.year, date.month, date.day);
        spots.add(FlSpot((29 - j).toDouble(), (_outstandingByDeptDaily[day]?[dept] ?? 0).toDouble()));
      }
      lineBarsData.add(LineChartBarData(
        spots: spots,
        isCurved: true,
        color: deptColors[i % deptColors.length],
        barWidth: 3,
        belowBarData: BarAreaData(show: false),
        dotData: const FlDotData(show: false),
      ));
    }

    return Column(
      children: [
        const Text('Outstanding Job Cards by Department (Last 30 days)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: true),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      if (value % 7 == 0) {
                        final date = now.subtract(Duration(days: 29 - value.toInt()));
                        return Text('${date.day}/${date.month}', style: const TextStyle(fontSize: 10));
                      }
                      return const Text('');
                    },
                  ),
                ),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true)),
              ),
              borderData: FlBorderData(show: true),
              lineBarsData: lineBarsData,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: allDepts.asMap().entries.map((entry) {
            final index = entry.key;
            final dept = entry.value;
            return FilterChip(
              avatar: CircleAvatar(backgroundColor: deptColors[index % deptColors.length], radius: 6),
              label: Text(dept),
              selected: _selectedDepts.contains(dept),
              onSelected: (selected) => setState(() => selected ? _selectedDepts.add(dept) : _selectedDepts.remove(dept)),
              backgroundColor: deptColors[index % deptColors.length].withValues(alpha: 51),
              selectedColor: deptColors[index % deptColors.length].withValues(alpha: 128),
              checkmarkColor: Colors.white,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAreaChart() {
    final now = DateTime.now();
    final allAreas = _outstandingByAreaDaily.values.expand((m) => m.keys).toSet().toList()..sort();
    const List<Color> deptColors = [Colors.green, Colors.blue, Colors.brown, Colors.red, Colors.orange, Colors.purple, Colors.teal, Colors.pink, Colors.indigo, Colors.amber, Colors.cyan, Colors.lime];

    final lineBarsData = <LineChartBarData>[];
    for (int i = 0; i < allAreas.length; i++) {
      final area = allAreas[i];
      if (!_selectedAreas.contains(area)) continue;
      final spots = <FlSpot>[];
      for (int j = 29; j >= 0; j--) {
        final date = now.subtract(Duration(days: j));
        final day = DateTime(date.year, date.month, date.day);
        spots.add(FlSpot((29 - j).toDouble(), (_outstandingByAreaDaily[day]?[area] ?? 0).toDouble()));
      }
      lineBarsData.add(LineChartBarData(
        spots: spots,
        isCurved: true,
        color: deptColors[i % deptColors.length],
        barWidth: 3,
        belowBarData: BarAreaData(show: false),
        dotData: const FlDotData(show: false),
      ));
    }

    return Column(
      children: [
        const Text('Outstanding Job Cards by Area (Last 30 days)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: true),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      if (value % 7 == 0) {
                        final date = now.subtract(Duration(days: 29 - value.toInt()));
                        return Text('${date.day}/${date.month}', style: const TextStyle(fontSize: 10));
                      }
                      return const Text('');
                    },
                  ),
                ),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true)),
              ),
              borderData: FlBorderData(show: true),
              lineBarsData: lineBarsData,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: allAreas.asMap().entries.map((entry) {
            final index = entry.key;
            final area = entry.value;
            return FilterChip(
              avatar: CircleAvatar(backgroundColor: deptColors[index % deptColors.length], radius: 6),
              label: Text(area),
              selected: _selectedAreas.contains(area),
              onSelected: (selected) => setState(() => selected ? _selectedAreas.add(area) : _selectedAreas.remove(area)),
              backgroundColor: deptColors[index % deptColors.length].withValues(alpha: 51),
              selectedColor: deptColors[index % deptColors.length].withValues(alpha: 128),
              checkmarkColor: Colors.white,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPieChart() {
    final allDepts = _filteredJobsCache.map((j) => j.department ?? 'Other').toSet().toList()..sort();
    const List<Color> deptColors = [Colors.green, Colors.blue, Colors.brown, Colors.red, Colors.orange, Colors.purple, Colors.teal, Colors.pink, Colors.indigo, Colors.amber, Colors.cyan, Colors.lime];
    final sections = <PieChartSectionData>[];

    for (int i = 0; i < allDepts.length; i++) {
      final dept = allDepts[i];
      if (!_selectedPieDepts.contains(dept)) continue;
      final count = _filteredJobsCache.where((j) => j.status == JobStatus.open && j.department == dept).length;
      if (count > 0) {
        sections.add(PieChartSectionData(
          value: count.toDouble(),
          color: deptColors[i % deptColors.length],
          title: '$count',
          radius: 80,
          titleStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ));
      }
    }

    return Column(
      children: [
        const Text('Open Job Cards by Department', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        SizedBox(
          height: 220,
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 40,
              sectionsSpace: 2,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: allDepts.asMap().entries.map((entry) {
            final index = entry.key;
            final dept = entry.value;
            return FilterChip(
              avatar: CircleAvatar(backgroundColor: deptColors[index % deptColors.length], radius: 6),
              label: Text(dept),
              selected: _selectedPieDepts.contains(dept),
              onSelected: (selected) => setState(() => selected ? _selectedPieDepts.add(dept) : _selectedPieDepts.remove(dept)),
              backgroundColor: deptColors[index % deptColors.length].withValues(alpha: 51),
              selectedColor: deptColors[index % deptColors.length].withValues(alpha: 128),
              checkmarkColor: Colors.white,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTabbedAnalytics() {
    return const Text('Mobile Tabbed Analytics (expand if needed)');
  }

    Widget _buildLiveJobCardsList() {
    if (_filteredJobsCache.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No active jobs')),
        ),
      );
    }

    return AnimationLimiter(
      child: Column(
        children: [
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _filteredJobsCache.length > 10 ? 10 : _filteredJobsCache.length,
            itemBuilder: (context, index) {
              final job = _filteredJobsCache[index];
              return AnimationConfiguration.staggeredList(
                position: index,
                duration: const Duration(milliseconds: 375),
                child: SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(
                    child: _buildJobCardWidget(job),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (currentEmployee?.position.toLowerCase().contains('manager') != true) {
      return const Scaffold(
        body: Center(child: Text('Access denied. Manager role required.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Manager Dashboard - Job Card Program',
          style: TextStyle(fontSize: _isMobile ? 16 : 20),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF8C42), Color.fromARGB(255, 124, 124, 124)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          if (!_isMobile) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Last updated: ${_getLastUpdatedText()}', style: const TextStyle(fontSize: 13, color: Colors.white70)),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: () => _loadDashboardData(selectedDept, selectedMonth),
                ),
              ],
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: 'Refresh (${_getLastUpdatedText()})',
              onPressed: () => _loadDashboardData(selectedDept, selectedMonth),
            ),
          ],
          IconButton(icon: const Icon(Icons.file_download), onPressed: _showExportOptions),
          IconButton(
            icon: const Icon(Icons.inventory),
            tooltip: 'Copper Inventory',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CopperDashboardScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          const SyncIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await _loadDashboardData(selectedDept, selectedMonth);
                await Future.delayed(const Duration(milliseconds: 500));
              },
              child: SingleChildScrollView(
                padding: EdgeInsets.all(_screenPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StreamBuilder<List<ConnectivityResult>>(
                      stream: _connectivityService.connectivityStream,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
                        final isOnline = snapshot.data!.any((r) => r != ConnectivityResult.none);
                        if (isOnline) return const SizedBox.shrink();
                        return Container(
                          width: double.infinity,
                          color: Colors.red,
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 16),
                          child: const Text('Offline Mode - Data may be outdated', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        );
                      },
                    ),
              if (_isLoading)
                const Column(
                  children: [
                    SkeletonLoader(height: 80),
                    SizedBox(height: 16),
                    SkeletonLoader(height: 80),
                    SizedBox(height: 16),
                    SkeletonLoader(height: 80),
                    SizedBox(height: 16),
                    SkeletonLoader(height: 300),
                  ],
                )
              else
                Column(
                  children: [
                                        // Filters card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _isMobile
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  DropdownButton<String?>(
                                    value: selectedDept,
                                    hint: const Text('All Departments'),
                                    isExpanded: true,
                                    items: [
                                      const DropdownMenuItem<String?>(value: null, child: Text('All Departments'))
                                    ] +
                                        (_departments ?? []).map((d) => DropdownMenuItem<String?>(value: d, child: Text(d))).toList(),
                                    onChanged: (String? v) {
                                      setState(() => selectedDept = v);
                                      _loadDashboardData(selectedDept, selectedMonth);
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: _showMonthPicker,
                                          child: Text(
                                            selectedMonth == null ? 'Select Month' : '${selectedMonth!.month}/${selectedMonth!.year}',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: () {
                                            setState(() {
                                              selectedDept = null;
                                              selectedMonth = null;
                                            });
                                            _loadDashboardData();
                                          },
                                          child: const Text('Clear'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(
                                    child: DropdownButton<String?>(
                                      value: selectedDept,
                                      hint: const Text('All Departments'),
                                      items: [
                                        const DropdownMenuItem<String?>(value: null, child: Text('All Departments'))
                                      ] +
                                          (_departments ?? []).map((d) => DropdownMenuItem<String?>(value: d, child: Text(d))).toList(),
                                      onChanged: (String? v) {
                                        setState(() => selectedDept = v);
                                        _loadDashboardData(selectedDept, selectedMonth);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  ElevatedButton(
                                    onPressed: _showMonthPicker,
                                    child: Text(selectedMonth == null ? 'Select Month' : '${selectedMonth!.month}/${selectedMonth!.year}'),
                                  ),
                                  const SizedBox(width: 16),
                                  ElevatedButton(
                                    onPressed: () {
                                      setState(() {
                                        selectedDept = null;
                                        selectedMonth = null;
                                      });
                                      _loadDashboardData();
                                    },
                                    child: const Text('Clear Filters'),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    SizedBox(height: _sectionSpacing),
                    _buildMetricsSection(),
                    SizedBox(height: _sectionSpacing),
                    Text('Analytics & Breakdowns', style: TextStyle(fontSize: _isDesktop ? 26 : 24, fontWeight: FontWeight.bold)),
                    SizedBox(height: _isDesktop ? 24 : 16),
                     _buildChartsSection(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  ),
);
  }
}