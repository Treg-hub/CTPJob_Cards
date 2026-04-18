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
import 'copper_dashboard_screen.dart';

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

      _totalJobs = jobs.length;
      _openJobsCount = jobs.where((j) => j.status == JobStatus.open).length;

      final now = DateTime.now();
      _completed7Days = jobs.where((j) => j.status == JobStatus.completed && j.completedAt != null && j.completedAt!.isAfter(now.subtract(const Duration(days: 7)))).length;
      _completed30Days = jobs.where((j) => j.status == JobStatus.completed && j.completedAt != null && j.completedAt!.isAfter(now.subtract(const Duration(days: 30)))).length;

      final completedInPeriod = jobs.where((j) => j.status == JobStatus.completed).length;
      _completionRate = _totalJobs > 0 ? (completedInPeriod / _totalJobs * 100) : 0.0;

      final completedJobs = jobs.where((j) => j.status == JobStatus.completed && j.createdAt != null && j.completedAt != null).toList();
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
      itemCount: 6,
      itemBuilder: (context, index) {
        final data = [
          {'title': 'Total Jobs', 'value': _totalJobs.toString(), 'color': Colors.blue},
          {'title': 'Open Jobs', 'value': _openJobsCount.toString(), 'color': Colors.orange},
          {'title': 'Completed (7d)', 'value': _completed7Days.toString(), 'color': Colors.green},
          {'title': 'Completion %', 'value': '${_completionRate.toStringAsFixed(0)}%', 'color': Colors.purple},
          {'title': 'Pending Assign', 'value': _pendingAssignments.toString(), 'color': Colors.red},
          {'title': 'Aged >7d', 'value': _agedOpen7d.toString(), 'color': Colors.redAccent},
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
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Trend (Last 30 days)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: true),
                  titlesData: const FlTitlesData(show: true),
                  borderData: FlBorderData(show: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: List.generate(30, (i) => FlSpot(i.toDouble(), (i % 5).toDouble())),
                      isCurved: true,
                      color: Colors.orange,
                      barWidth: 3,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabbedAnalytics() {
    return const Text('Mobile Tabbed Analytics (expand if needed)');
  }

  Widget _buildTrendChart() {
    return const SizedBox(height: 200, child: Center(child: Text('Trend Chart')));
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
      child: ListView.builder(
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
                child: Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(job.description),
                    subtitle: Text('${job.department} • ${job.status.displayName}'),
                    trailing: Text('P${job.priority}'),
                  ),
                ),
              ),
            ),
          );
        },
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
              onRefresh: () => _loadDashboardData(selectedDept, selectedMonth),
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
                    if (_isMobile) _buildTabbedAnalytics() else _buildChartsSection(),
                    const SizedBox(height: 24),
                    _buildTrendChart(),
                    SizedBox(height: _sectionSpacing),
                    Text('Live Active Job Cards', style: TextStyle(fontSize: _isDesktop ? 26 : 24, fontWeight: FontWeight.bold)),
                    SizedBox(height: _isDesktop ? 24 : 16),
                    _buildLiveJobCardsList(),
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