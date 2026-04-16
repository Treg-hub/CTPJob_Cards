import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/job_card.dart';
import '../services/connectivity_service.dart';
import '../services/firestore_service.dart';
import '../main.dart' show currentEmployee;
import 'view_job_cards_screen.dart';
import 'copper_dashboard_screen.dart';

class ManagerDashboardScreen extends StatefulWidget {
  const ManagerDashboardScreen({super.key});

  @override
  State<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends State<ManagerDashboardScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  // Dashboard data - expanded KPIs for better Job Card / Breakdown tracking
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
  Map<String, int> _employeePerformance = {};
  Map<String, int> _priorityBreakdown = {};
  Map<String, int> _typeBreakdown = {};
  Map<String, int> _machineBreakdown = {};

  // New KPIs
  double _backlogTrend = 0.0;
  Duration? _avgTimeToAssign;
  int _avgDaysOpen = 0;

  bool _isLoading = true;

  // Filters
  String? selectedDept;
  DateTime? selectedMonth;
  List<String>? _departments;

  // Trend data
  List<FlSpot> createdSpots = [];
  List<FlSpot> completedSpots = [];

  // Cached filtered job list for drill-down, export, and performance
  List<JobCard> _filteredJobsCache = [];

  // Last updated timestamp (keeps costs low - on-demand only)
  DateTime? _lastUpdated;

  // Responsive design helpers
  bool get _isMobile => MediaQuery.of(context).size.width < 600;
  bool get _isTablet => MediaQuery.of(context).size.width >= 600 && MediaQuery.of(context).size.width < 1200;
  bool get _isDesktop => MediaQuery.of(context).size.width >= 1200;

  int get _metricsCrossAxisCount {
    if (_isDesktop) return 6;
    if (_isTablet) return 4;
    return 2;
  }

  double get _screenPadding {
    if (_isDesktop) return 32;
    if (_isTablet) return 24;
    return 16;
  }

  double get _sectionSpacing {
    if (_isDesktop) return 32;
    if (_isTablet) return 24;
    return 16;
  }

  // Analytics tab index for mobile/tabbed view
  int _analyticsTabIndex = 0;

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
      final openQuery = _jobCardsCollection.where('status', isEqualTo: 'open');
      final completedQuery = _jobCardsCollection.where('status', isEqualTo: 'completed');
      final openSnapshot = await openQuery.get();
      final completedSnapshot = await completedQuery.get();
      final openDepts = openSnapshot.docs.map((doc) => doc.data().department).where((d) => d.isNotEmpty).toSet();
      final completedDepts = completedSnapshot.docs.map((doc) => doc.data().department).where((d) => d.isNotEmpty).toSet();
      _departments = (openDepts.union(completedDepts)).toList()..sort();
      if (mounted) setState(() {});
    } catch (e) {
      // silent fail
    }
  }

  Future<void> _loadDashboardData([String? dept, DateTime? month]) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      Query<JobCard> query = _jobCardsCollection;

      // Server-side filtering (keeps costs low)
      if (dept != null && dept.isNotEmpty) {
        query = query.where('department', isEqualTo: dept);
      }

      if (month != null) {
        final start = DateTime(month.year, month.month, 1);
        final end = DateTime(month.year, month.month + 1, 1).subtract(const Duration(days: 1));
        query = query
            .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end));
      }

      final snapshot = await query.get();
      final filteredJobs = snapshot.docs.map((doc) => doc.data()).toList();

      // Cache for drill-down and export
      _filteredJobsCache = filteredJobs;

      // Core KPIs (all respect filters)
      _totalJobs = filteredJobs.length;
      _openJobsCount = filteredJobs.where((j) => j.status == JobStatus.open).length;

      final now = DateTime.now();
      _completed7Days = filteredJobs
          .where((j) =>
              j.status == JobStatus.completed &&
              j.completedAt != null &&
              j.completedAt!.isAfter(now.subtract(const Duration(days: 7))))
          .length;
      _completed30Days = filteredJobs
          .where((j) =>
              j.status == JobStatus.completed &&
              j.completedAt != null &&
              j.completedAt!.isAfter(now.subtract(const Duration(days: 30))))
          .length;

      final completedInPeriod = filteredJobs.where((j) => j.status == JobStatus.completed).length;
      _completionRate = _totalJobs > 0 ? (completedInPeriod / _totalJobs * 100) : 0.0;

      // Average completion time (MTTR)
      final completedJobs = filteredJobs.where((j) => j.status == JobStatus.completed && j.createdAt != null && j.completedAt != null).toList();
      if (completedJobs.isNotEmpty) {
        var totalDuration = Duration.zero;
        for (var j in completedJobs) {
          totalDuration += j.completedAt!.difference(j.createdAt!);
        }
        _averageCompletionTime = totalDuration ~/ completedJobs.length;
      } else {
        _averageCompletionTime = null;
      }

      // Average Response Time
      final responseJobs = filteredJobs.where((j) => j.createdAt != null && j.assignedAt != null).toList();
      if (responseJobs.isNotEmpty) {
        var totalResponse = Duration.zero;
        for (var j in responseJobs) {
          totalResponse += j.assignedAt!.difference(j.createdAt!);
        }
        _avgResponseTime = totalResponse ~/ responseJobs.length;
      } else {
        _avgResponseTime = null;
      }

      // New KPI: Avg Time to Assign
      if (responseJobs.isNotEmpty) {
        _avgTimeToAssign = _avgResponseTime;
      } else {
        _avgTimeToAssign = null;
      }

      // Pending assignments
      _pendingAssignments = filteredJobs.where((j) => j.status == JobStatus.open && (j.assignedClockNos == null || j.assignedClockNos!.isEmpty)).length;

      // Aged backlog
      final openJobs = filteredJobs.where((j) => j.status == JobStatus.open && j.createdAt != null).toList();
      _agedOpen7d = openJobs.where((j) => j.createdAt!.isBefore(now.subtract(const Duration(days: 7)))).length;
      _agedOpen30d = openJobs.where((j) => j.createdAt!.isBefore(now.subtract(const Duration(days: 30)))).length;

      // New KPI: Average days open
      if (openJobs.isNotEmpty) {
        var totalDays = 0;
        for (var j in openJobs) {
          totalDays += now.difference(j.createdAt!).inDays;
        }
        _avgDaysOpen = totalDays ~/ openJobs.length;
      } else {
        _avgDaysOpen = 0;
      }

      // Backlog Trend
      final previousPeriodQuery = _jobCardsCollection
          .where('status', isEqualTo: 'open')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(now.subtract(const Duration(days: 60))))
          .where('createdAt', isLessThan: Timestamp.fromDate(now.subtract(const Duration(days: 30))));
      final prevSnapshot = await previousPeriodQuery.get();
      final prevOpen = prevSnapshot.docs.length;
      final currentOpen = _openJobsCount;
      _backlogTrend = prevOpen > 0 ? ((currentOpen - prevOpen) / prevOpen * 100) : 0.0;

      // Employee performance
      _employeePerformance = {};
      for (var j in completedJobs) {
        if (j.completedBy != null) {
          _employeePerformance[j.completedBy!] = (_employeePerformance[j.completedBy!] ?? 0) + 1;
        }
      }

      // Priority breakdown
      _priorityBreakdown = {};
      for (var j in filteredJobs) {
        final key = j.status == JobStatus.open ? 'Open P${j.priority}' : 'Completed P${j.priority}';
        _priorityBreakdown[key] = (_priorityBreakdown[key] ?? 0) + 1;
      }

      // Type breakdown
      _typeBreakdown = {};
      for (var j in filteredJobs) {
        final key = j.status == JobStatus.open ? 'Open ${j.type.displayName}' : 'Completed ${j.type.displayName}';
        _typeBreakdown[key] = (_typeBreakdown[key] ?? 0) + 1;
      }

      // Machine breakdown
      _machineBreakdown = {};
      for (final j in filteredJobs) {
        final key = j.machine.trim().isNotEmpty ? j.machine : 'Unknown Machine';
        _machineBreakdown[key] = (_machineBreakdown[key] ?? 0) + 1;
      }

      // Trend data (30 days)
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      final createdPerDay = <DateTime, int>{};
      final completedPerDay = <DateTime, int>{};
      for (var job in filteredJobs) {
        if (job.createdAt != null && job.createdAt!.isAfter(thirtyDaysAgo)) {
          final day = DateTime(job.createdAt!.year, job.createdAt!.month, job.createdAt!.day);
          createdPerDay[day] = (createdPerDay[day] ?? 0) + 1;
        }
        if (job.completedAt != null && job.completedAt!.isAfter(thirtyDaysAgo)) {
          final day = DateTime(job.completedAt!.year, job.completedAt!.month, job.completedAt!.day);
          completedPerDay[day] = (completedPerDay[day] ?? 0) + 1;
        }
      }
      createdSpots.clear();
      completedSpots.clear();
      for (int i = 0; i < 30; i++) {
        final day = thirtyDaysAgo.add(Duration(days: i));
        final x = i.toDouble();
        createdSpots.add(FlSpot(x, (createdPerDay[day] ?? 0).toDouble()));
        completedSpots.add(FlSpot(x, (completedPerDay[day] ?? 0).toDouble()));
      }

      // Record last updated time (low-cost solution)
      _lastUpdated = DateTime.now();

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading dashboard: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}d ${duration.inHours % 24}h';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else {
      return '${duration.inMinutes}m';
    }
  }

  // Helper to show friendly "Last updated" text
  String _getLastUpdatedText() {
    if (_lastUpdated == null) return 'Never';
    final diff = DateTime.now().difference(_lastUpdated!);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${_lastUpdated!.day}/${_lastUpdated!.month} ${_lastUpdated!.hour}:${_lastUpdated!.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (currentEmployee == null || !currentEmployee!.position.toLowerCase().contains('manager')) {
      return const Scaffold(
        body: Center(
          child: Text('Access denied. Manager role required.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manager Dashboard - Job Card Program'),
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
          // Prominent Refresh button + Last Updated
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Last updated: ${_getLastUpdatedText()}',
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                tooltip: 'Refresh dashboard',
                onPressed: () => _loadDashboardData(selectedDept, selectedMonth),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _showExportOptions,
          ),
          IconButton(
            icon: const Icon(Icons.inventory),
            tooltip: 'Copper Inventory',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CopperDashboardScreen())),
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingSkeleton()
          : RefreshIndicator(
              onRefresh: () => _loadDashboardData(selectedDept, selectedMonth),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(_screenPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Offline indicator
                    Consumer<ConnectivityService>(
                      builder: (context, connectivity, child) {
                        return StreamBuilder<List<ConnectivityResult>>(
                          stream: connectivity.connectivityStream,
                          builder: (context, snapshot) {
                            if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
                            final isOnline = snapshot.data!.any((r) => r != ConnectivityResult.none);
                            if (isOnline) return const SizedBox.shrink();
                            return Container(
                              width: double.infinity,
                              color: Colors.red,
                              padding: const EdgeInsets.all(8),
                              margin: const EdgeInsets.only(bottom: 16),
                              child: const Text(
                                'Offline Mode - Data may be outdated',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            );
                          },
                        );
                      },
                    ),
                    // Filters
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
                                            selectedMonth == null ? 'Select Month' : '${_getMonthName(selectedMonth!.month)} ${selectedMonth!.year}',
                                            overflow: TextOverflow.ellipsis,
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
                                    child: Text(selectedMonth == null ? 'Select Month' : '${_getMonthName(selectedMonth!.month)} ${selectedMonth!.year}'),
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

                    // KPIs - horizontal scroll on mobile
                    _buildMetricsSection(),

                    SizedBox(height: _sectionSpacing),

                    // Analytics header + tabbed view on mobile
                    Text(
                      'Analytics & Breakdowns',
                      style: TextStyle(
                        fontSize: _isDesktop ? 26 : 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: _isDesktop ? 24 : 16),

                    if (_isMobile)
                      _buildTabbedAnalytics()
                    else
                      _buildChartsSection(),

                    const SizedBox(height: 24),
                    _buildTrendChart(),

                    SizedBox(height: _sectionSpacing),

                    // Live Job Cards List
                    Text(
                      'Live Active Job Cards',
                      style: TextStyle(
                        fontSize: _isDesktop ? 26 : 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: _isDesktop ? 24 : 16),
                    _buildLiveJobCardsList(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFFFF8C42)),
          SizedBox(height: 16),
          Text('Loading dashboard...', style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildMetricsSection() {
    final metrics = [
      _buildMetricCard('Total Jobs', _totalJobs.toString(), Icons.assignment, Colors.indigo),
      _buildMetricCard('Open Jobs', _openJobsCount.toString(), Icons.pending_actions, Colors.orange),
      _buildMetricCard('Completed (7d)', _completed7Days.toString(), Icons.check_circle_outline, Colors.green),
      _buildMetricCard('Completed (30d)', _completed30Days.toString(), Icons.timeline, Colors.blue),
      _buildMetricCard('Completion Rate', '${_completionRate.toStringAsFixed(0)}%', Icons.percent, Colors.teal),
      _buildMetricCard('Avg Completion', _averageCompletionTime != null ? _formatDuration(_averageCompletionTime!) : 'N/A', Icons.schedule, Colors.purple),
      _buildMetricCard('Avg Response', _avgResponseTime != null ? _formatDuration(_avgResponseTime!) : 'N/A', Icons.timer, Colors.amber),
      _buildMetricCard('Pending Assign', _pendingAssignments.toString(), Icons.person_off, Colors.redAccent),
      _buildMetricCard('Aged >7d', _agedOpen7d.toString(), Icons.warning_amber, Colors.deepOrange),
      _buildMetricCard('Aged >30d', _agedOpen30d.toString(), Icons.dangerous, Colors.red),
      _buildMetricCard('Backlog Trend', '${_backlogTrend.toStringAsFixed(0)}%', _backlogTrend >= 0 ? Icons.arrow_upward : Icons.arrow_downward, _backlogTrend >= 0 ? Colors.red : Colors.green),
      _buildMetricCard('Avg Time to Assign', _avgTimeToAssign != null ? _formatDuration(_avgTimeToAssign!) : 'N/A', Icons.timer_outlined, Colors.lime),
      _buildMetricCard('Avg Days Open', _avgDaysOpen.toString(), Icons.today, Colors.cyan),
    ];

    if (_isMobile) {
      return SizedBox(
        height: 140,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: metrics.length,
          itemBuilder: (context, index) => Container(
            width: 140,
            margin: const EdgeInsets.only(right: 12),
            child: metrics[index],
          ),
        ),
      );
    }
    return GridView.count(
      crossAxisCount: _metricsCrossAxisCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: _isDesktop ? 20 : 16,
      mainAxisSpacing: _isDesktop ? 20 : 16,
      children: metrics,
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Semantics(
      label: '$title: $value',
      value: value,
      child: Card(
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 12),
              Text(
                value,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabbedAnalytics() {
    return Column(
      children: [
        SegmentedButton<int>(
          segments: [
            ButtonSegment(value: 0, label: Text('Priority & Type')),
            ButtonSegment(value: 1, label: Text('Machines & Performance')),
          ],
          selected: {_analyticsTabIndex},
          onSelectionChanged: (Set<int> selection) {
            setState(() => _analyticsTabIndex = selection.first);
          },
        ),
        const SizedBox(height: 16),
        _analyticsTabIndex == 0
            ? Column(
                children: [
                  _buildPriorityChart(),
                  const SizedBox(height: 16),
                  _buildTypeChart(),
                ],
              )
            : Column(
                children: [
                  _buildTopMachinesChart(),
                  const SizedBox(height: 16),
                  _buildEmployeePerformanceChart(),
                ],
              ),
      ],
    );
  }

  Widget _buildChartsSection({bool isTabbed = false}) {
    if (_isDesktop || isTabbed) {
      return Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildPriorityChart()),
              const SizedBox(width: 24),
              Expanded(child: _buildTypeChart()),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildTopMachinesChart()),
              const SizedBox(width: 24),
              Expanded(child: _buildEmployeePerformanceChart()),
            ],
          ),
        ],
      );
     } else {
       return Column(
         children: [
           _buildPriorityChart(),
           SizedBox(height: _sectionSpacing),
           _buildTypeChart(),
           SizedBox(height: _sectionSpacing),
           _buildTopMachinesChart(),
           SizedBox(height: _sectionSpacing),
           _buildEmployeePerformanceChart(),
         ],
       );
     }
  }

  Widget _buildPriorityChart() {
    final priorities = ['P1', 'P2', 'P3', 'P4', 'P5'];

    final sections = <PieChartSectionData>[];

    for (int i = 0; i < priorities.length; i++) {
      final openKey = 'Open ${priorities[i]}';
      final completedKey = 'Completed ${priorities[i]}';
      final total = (_priorityBreakdown[openKey] ?? 0) + (_priorityBreakdown[completedKey] ?? 0);
      if (total > 0) {
        sections.add(PieChartSectionData(
          value: total.toDouble(),
          color: _getPriorityColor(priorities[i]),
          title: priorities[i],
          radius: 55,
          titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
        ));
      }
    }

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Priority Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: _isMobile ? 140 : 220,
              child: sections.isEmpty
                  ? const Center(child: Text('No data available'))
                  : PieChart(
                      PieChartData(
                        sections: sections,
                        centerSpaceRadius: 40,
                        sectionsSpace: 4,
                        pieTouchData: PieTouchData(
                          touchCallback: (FlTouchEvent event, PieTouchResponse? response) {
                            if (event is FlTapUpEvent && response != null && response.touchedSection != null) {
                              final index = response.touchedSection!.touchedSectionIndex;
                              if (index >= 0 && index < priorities.length) {
                                final priority = index + 1;
                                final filtered = _filteredJobsCache.where((j) => j.priority == priority).toList();
                                _showFilteredJobCardsBottomSheet('Priority P$priority', filtered);
                              }
                            }
                          },
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: priorities.map((p) {
                final total = (_priorityBreakdown['Open $p'] ?? 0) + (_priorityBreakdown['Completed $p'] ?? 0);
                return _buildLegendItem('$p ($total)', _getPriorityColor(p));
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChart() {
    final sections = <PieChartSectionData>[];
    final typeKeys = _typeBreakdown.keys.toList();
    final colors = [Colors.blue, Colors.teal, Colors.indigo, Colors.cyan];
    int colorIndex = 0;

    for (var key in typeKeys) {
      final value = _typeBreakdown[key] ?? 0;
      if (value > 0) {
        sections.add(PieChartSectionData(
          value: value.toDouble(),
          color: colors[colorIndex % colors.length],
          title: key,
          radius: 55,
          titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        ));
        colorIndex++;
      }
    }

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Job Type Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: _isMobile ? 120 : 220,
              child: sections.isEmpty
                  ? const Center(child: Text('No data available'))
                  : PieChart(
                      PieChartData(
                        sections: sections,
                        centerSpaceRadius: 40,
                        sectionsSpace: 4,
                        pieTouchData: PieTouchData(
                          touchCallback: (FlTouchEvent event, PieTouchResponse? response) {
                            if (event is FlTapUpEvent && response != null && response.touchedSection != null) {
                              final index = response.touchedSection!.touchedSectionIndex;
                              if (index >= 0 && index < typeKeys.length) {
                                final key = typeKeys[index];
                                final parts = key.split(' ');
                                final statusStr = parts[0];
                                final typeName = parts.sublist(1).join(' ');
                                final status = statusStr == 'Open' ? JobStatus.open : JobStatus.completed;
                                final filtered = _filteredJobsCache.where((j) => j.status == status && j.type.displayName == typeName).toList();
                                _showFilteredJobCardsBottomSheet(key, filtered);
                              }
                            }
                          },
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: List.generate(typeKeys.length, (i) => _buildLegendItem('${typeKeys[i]} (${_typeBreakdown[typeKeys[i]]})', colors[i % colors.length])),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopMachinesChart() {
    if (_machineBreakdown.isEmpty) {
      return const Card(
        elevation: 6,
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: Text('No machine data yet')),
        ),
      );
    }

    final sortedMachines = _machineBreakdown.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topMachines = sortedMachines.take(5).toList();

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Top Machines by Breakdowns', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: _isMobile ? 200 : 250,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: topMachines.isNotEmpty ? topMachines.first.value.toDouble() + 3 : 10,
                  barGroups: List.generate(topMachines.length, (index) {
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: topMachines[index].value.toDouble(),
                          color: const Color(0xFFFF8C42),
                          width: 22,
                          borderRadius: const BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6)),
                        ),
                      ],
                    );
                  }),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() < topMachines.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                topMachines[value.toInt()].key.length > 8
                                    ? '${topMachines[value.toInt()].key.substring(0, 8)}...'
                                    : topMachines[value.toInt()].key,
                                style: const TextStyle(fontSize: 10),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    touchCallback: (FlTouchEvent event, BarTouchResponse? response) {
                      if (event is FlTapUpEvent && response != null && response.spot != null) {
                        final index = response.spot!.touchedBarGroupIndex;
                        if (index >= 0 && index < topMachines.length) {
                          final machine = topMachines[index].key;
                          final filtered = _filteredJobsCache.where((j) => j.machine == machine).toList();
                          _showFilteredJobCardsBottomSheet('Machine: $machine', filtered);
                        }
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeePerformanceChart() {
    if (_employeePerformance.isEmpty) {
      return const Card(
        elevation: 6,
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: Text('No completed jobs data available')),
        ),
      );
    }

    final sortedEmployees = _employeePerformance.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topEmployees = sortedEmployees.take(3).toList();

    final sections = <PieChartSectionData>[];
    final colors = [Colors.indigo, Colors.blue, Colors.teal];

    for (int i = 0; i < topEmployees.length; i++) {
      sections.add(PieChartSectionData(
        value: topEmployees[i].value.toDouble(),
        color: colors[i % colors.length],
        title: topEmployees[i].key,
        radius: 55,
        titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
      ));
    }

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Top 3 Employee Performance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: _isMobile ? 120 : 220,
              child: sections.isEmpty
                  ? const Center(child: Text('No data available'))
                  : PieChart(
                      PieChartData(
                        sections: sections,
                        centerSpaceRadius: 40,
                        sectionsSpace: 4,
                        pieTouchData: PieTouchData(
                          touchCallback: (FlTouchEvent event, PieTouchResponse? response) {
                            if (event is FlTapUpEvent && response != null && response.touchedSection != null) {
                              final index = response.touchedSection!.touchedSectionIndex;
                              if (index >= 0 && index < topEmployees.length) {
                                final employee = topEmployees[index].key;
                                final filtered = _filteredJobsCache.where((j) => j.completedBy == employee).toList();
                                _showFilteredJobCardsBottomSheet('Employee: $employee', filtered);
                              }
                            }
                          },
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: List.generate(topEmployees.length, (i) => _buildLegendItem(topEmployees[i].key, colors[i % colors.length])),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendChart() {
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Created vs Completed Trend (30 days)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: _isMobile ? 200 : 250,
              child: LineChart(
                LineChartData(
                  lineBarsData: [
                    LineChartBarData(
                      spots: createdSpots,
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 3,
                      belowBarData: BarAreaData(show: false),
                    ),
                    LineChartBarData(
                      spots: completedSpots,
                      isCurved: true,
                      color: Colors.green,
                      barWidth: 3,
                      belowBarData: BarAreaData(show: false),
                    ),
                  ],
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final day = thirtyDaysAgo.add(Duration(days: value.toInt()));
                          return Text('${day.day}/${day.month}');
                        },
                        interval: 5,
                      ),
                    ),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(show: true),
                  borderData: FlBorderData(show: true),
                  lineTouchData: LineTouchData(
                    touchCallback: (FlTouchEvent event, LineTouchResponse? response) {
                      if (event is FlTapUpEvent && response != null && response.lineBarSpots != null && response.lineBarSpots!.isNotEmpty) {
                        final spot = response.lineBarSpots!.first;
                        final dayIndex = spot.x.toInt();
                        final day = thirtyDaysAgo.add(Duration(days: dayIndex));
                        final filtered = _filteredJobsCache.where((j) => j.createdAt != null && j.createdAt!.isAfter(day) && j.createdAt!.isBefore(day.add(Duration(days: 1)))).toList();
                        _showFilteredJobCardsBottomSheet('Created on ${day.day}/${day.month}', filtered);
                      }
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildLegendItem('Created', Colors.blue),
                const SizedBox(width: 16),
                _buildLegendItem('Completed', Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Semantics(
      label: label,
      child: Row(
        children: [
          Container(width: 16, height: 16, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildLiveJobCardsList() {
    return StreamBuilder<List<JobCard>>(
      stream: _firestoreService.getAllJobCards(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(child: Text('Error loading live jobs: ${snapshot.error}', style: const TextStyle(color: Colors.red))),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Card(
            elevation: 6,
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final jobCards = snapshot.data!
            .where((job) => job.status != JobStatus.completed)
            .take(10)
            .toList();

        if (jobCards.isEmpty) {
          return const Card(
            elevation: 6,
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No active job cards - great job!')),
            ),
          );
        }

        return Card(
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFFF8C42),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.list_alt, color: Colors.black),
                    const SizedBox(width: 8),
                    Text(
                      'Recent Active Jobs (${jobCards.length})',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                  ],
                ),
              ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: jobCards.length,
                itemBuilder: (context, index) {
                  final job = jobCards[index];
                  return InkWell(
                    onTap: () => _showJobCardDetails(job),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: index < jobCards.length - 1 ? Colors.grey.withValues(alpha: 0.3) : Colors.transparent),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getPriorityColor('P${job.priority}'),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('P${job.priority}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(job.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                const SizedBox(height: 4),
                               Text('${job.type.displayName} • ${job.machine ?? "—"} • ${job.operator}', style: TextStyle(color: Colors.white, fontSize: 13)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: job.status == JobStatus.open ? Colors.blue.withValues(alpha: 128) : Colors.orange.withValues(alpha: 128),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(job.status.displayName, style: TextStyle(color: job.status == JobStatus.open ? Colors.blue : Colors.orange, fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.chevron_right, size: 24),
                        ],
                      ),
                    ),
                  );
                },
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
                ),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ViewJobCardsScreen())),
                    icon: const Icon(Icons.visibility),
                    label: const Text('View All Job Cards'),
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF8C42)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFilteredJobCardsBottomSheet(String filterType, List<JobCard> jobs) {
    final double initialSize = (0.4 + (jobs.length * 0.08)).clamp(0.4, 0.9);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: initialSize,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          padding: _isMobile ? const EdgeInsets.only(left: 8, right: 8, bottom: 8, top: 4) : const EdgeInsets.only(left: 12, right: 12, bottom: 12, top: 8),
          child: Column(
            children: [
              // Drag handle + title + dismiss
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$filterType Filtered Jobs',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (jobs.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      'No jobs match "$filterType"',
                      style: const TextStyle(color: Colors.grey, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: jobs.length,
                    itemBuilder: (context, index) {
                      final job = jobs[index];
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            border: Border.all(color: _getPriorityColor('P${job.priority}'), width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'P${job.priority}',
                            style: TextStyle(
                              color: _getPriorityColor('P${job.priority}'),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          job.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          '${job.type.displayName} • ${job.machine ?? "—"}',
                          style: const TextStyle(fontSize: 12, color: Colors.white),
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: () {
                          Navigator.pop(context);
                          _showJobCardDetails(job);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showExportOptions() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Export Dashboard'),
        content: Text('Choose format for the currently filtered data:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'csv'),
            child: Text('CSV'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'pdf'),
            child: Text('PDF'),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'csv') {
      await _exportToCSV();
    } else {
      await _exportToPDF();
    }
  }

  Future<void> _exportToCSV() async {
    final buffer = StringBuffer();
    buffer.writeln('Job Card Dashboard Export');
    buffer.writeln('Generated: ${DateTime.now()}');
    buffer.writeln('Filters: Department=${selectedDept ?? "All"}, Month=${selectedMonth != null ? _getMonthName(selectedMonth!.month) : "All"}');
    buffer.writeln('');
    buffer.writeln('KPIs,,,,');
    buffer.writeln('Total Jobs,$_totalJobs,,,,');
    buffer.writeln('Open Jobs,$_openJobsCount,,,,');
    buffer.writeln('Completion Rate,${_completionRate.toStringAsFixed(1)}%,,,,');
    buffer.writeln('');
    buffer.writeln('Job Cards,,,,');
    buffer.writeln('ID,Description,Type,Machine,Status');

    for (var job in _filteredJobsCache) {
      buffer.writeln('${job.id},${job.description.replaceAll(',', ' ')},${job.type.displayName},${job.machine ?? ""},${job.status.displayName}');
    }

    final csvString = buffer.toString();
    final bytes = utf8.encode(csvString);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/dashboard_export_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles([XFile(file.path)], text: 'Job Card Dashboard Export');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV exported and shared successfully')),
      );
    }
  }

  Future<void> _exportToPDF() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Job Card Dashboard Report',
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.orange800),
              ),
              pw.Text(
                'Generated: ${DateTime.now().toString().substring(0, 16)}',
                style: const pw.TextStyle(fontSize: 12),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Filters: Department = ${selectedDept ?? "All"} | Month = ${selectedMonth != null ? _getMonthName(selectedMonth!.month) : "All"}',
            style: const pw.TextStyle(fontSize: 14),
          ),
          pw.Divider(height: 30),

          pw.Text('Key Performance Indicators', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
            headers: ['Metric', 'Value'],
            data: [
              ['Total Jobs', _totalJobs.toString()],
              ['Open Jobs', _openJobsCount.toString()],
              ['Completed (7d)', _completed7Days.toString()],
              ['Completed (30d)', _completed30Days.toString()],
              ['Completion Rate', '${_completionRate.toStringAsFixed(1)}%'],
              ['Avg Completion Time', _averageCompletionTime != null ? _formatDuration(_averageCompletionTime!) : 'N/A'],
              ['Avg Response Time', _avgResponseTime != null ? _formatDuration(_avgResponseTime!) : 'N/A'],
              ['Pending Assignments', _pendingAssignments.toString()],
              ['Aged Open (>7d)', _agedOpen7d.toString()],
              ['Aged Open (>30d)', _agedOpen30d.toString()],
              ['Backlog Trend', '${_backlogTrend.toStringAsFixed(1)}%'],
              ['Avg Time to Assign', _avgTimeToAssign != null ? _formatDuration(_avgTimeToAssign!) : 'N/A'],
              ['Avg Days Open', _avgDaysOpen.toString()],
            ],
          ),
          pw.SizedBox(height: 30),

          pw.Text('Breakdowns', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.Text('Top Machines by Breakdowns:', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          ..._machineBreakdown.entries.take(5).map((entry) => pw.Text('• ${entry.key}: ${entry.value} jobs')),

          pw.SizedBox(height: 20),

          pw.Text('Filtered Job Cards (${_filteredJobsCache.length})', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
            headers: ['Description', 'Type', 'Machine', 'Status', 'Priority'],
            data: _filteredJobsCache
                .map((job) => [
                      job.description,
                      job.type.displayName,
                      job.machine ?? '-',
                      job.status.displayName,
                      'P${job.priority}',
                    ])
                .toList(),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/dashboard_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles([XFile(file.path)], text: 'Job Card Dashboard PDF Report');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF exported and shared successfully')),
      );
    }
  }

  void _showJobCardDetails(JobCard jobCard) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: _getPriorityColor('P${jobCard.priority}'), borderRadius: BorderRadius.circular(20)),
              child: Text('P${jobCard.priority}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('Job Card Details', style: const TextStyle(fontSize: 20))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Description', jobCard.description),
              _buildDetailRow('Type', jobCard.type.displayName),
              _buildDetailRow('Priority', 'P${jobCard.priority}'),
              _buildDetailRow('Status', jobCard.status.displayName),
              _buildDetailRow('Department', jobCard.department),
              _buildDetailRow('Area', jobCard.area),
              _buildDetailRow('Machine', jobCard.machine ?? '—'),
              _buildDetailRow('Part', jobCard.part ?? '—'),
              _buildDetailRow('Operator', jobCard.operator),
              if (jobCard.operatorClockNo != null) _buildDetailRow('Operator ID', jobCard.operatorClockNo!),
              if (jobCard.assignedClockNos?.isNotEmpty ?? false) _buildDetailRow('Assigned To', jobCard.assignedNames?.join(', ') ?? 'Unassigned'),
              if (jobCard.notes.isNotEmpty) _buildDetailRow('Notes', jobCard.notes),
              if (jobCard.createdAt != null) _buildDetailRow('Created', _formatDateTime(jobCard.createdAt!)),
              if (jobCard.assignedAt != null) _buildDetailRow('Assigned', _formatDateTime(jobCard.assignedAt!)),
              if (jobCard.startedAt != null) _buildDetailRow('Started', _formatDateTime(jobCard.startedAt!)),
              if (jobCard.lastUpdatedAt != null) _buildDetailRow('Last Updated', _formatDateTime(jobCard.lastUpdatedAt!)),
              if (jobCard.notificationReceivedAt != null) _buildDetailRow('Notification Read', _formatDateTime(jobCard.notificationReceivedAt!)),
              if (jobCard.completedAt != null) _buildDetailRow('Completed', _formatDateTime(jobCard.completedAt!)),
              if (jobCard.completedBy != null) _buildDetailRow('Completed By', jobCard.completedBy!),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Close')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Edit flow for ${jobCard.description} opened')));
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF8C42), foregroundColor: Colors.black),
            child: Text('Edit Job'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Semantics(
      label: '$label: $value',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 15)),
            ),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 15, color: Colors.white))),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Color _getPriorityColor(String priority) {
    final num = int.tryParse(priority.substring(1)) ?? 0;
    switch (num) {
      case 1: return Colors.green[600]!;
      case 2: return Colors.lightGreen[500]!;
      case 3: return Colors.amber[600]!;
      case 4: return Colors.deepOrange[600]!;
      case 5: return const Color(0xFFFF3D00);
      default: return Colors.grey;
    }
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  Future<void> _showMonthPicker() async {
    int selectedYear = selectedMonth?.year ?? DateTime.now().year;
    int selectedMonthNum = selectedMonth?.month ?? DateTime.now().month;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Select Month'),
          content: Row(
            children: [
              Expanded(
                child: DropdownButton<int>(
                  value: selectedYear,
                  items: List.generate(DateTime.now().year - 2020 + 1, (i) => 2020 + i).map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))).toList(),
                  onChanged: (v) => setState(() => selectedYear = v!),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButton<int>(
                  value: selectedMonthNum,
                  items: List.generate(12, (i) => i + 1).map((m) => DropdownMenuItem(value: m, child: Text(_getMonthName(m)))).toList(),
                  onChanged: (v) => setState(() => selectedMonthNum = v!),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                selectedMonth = DateTime(selectedYear, selectedMonthNum);
                _loadDashboardData(selectedDept, selectedMonth);
                Navigator.pop(context);
              },
              child: const Text('Select'),
            ),
          ],
        ),
      ),
    );
  }
}