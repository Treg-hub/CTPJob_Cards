import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
import '../main.dart' show currentEmployee;
import 'view_job_cards_screen.dart';

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

  bool _isLoading = true;

  // Filters
  String? selectedDept;
  DateTime? selectedMonth;
  List<String>? _departments;

  // Trend data
  List<FlSpot> createdSpots = [];
  List<FlSpot> completedSpots = [];

  // Responsive design helpers
  bool get _isMobile => MediaQuery.of(context).size.width < 600;
  bool get _isTablet => MediaQuery.of(context).size.width >= 600 && MediaQuery.of(context).size.width < 1200;
  bool get _isDesktop => MediaQuery.of(context).size.width >= 1200;

  int get _metricsCrossAxisCount {
    if (_isDesktop) return 6;
    if (_isTablet) return 4;
    return 2; // Mobile
  }

  double get _screenPadding {
    if (_isDesktop) return 32;
    if (_isTablet) return 24;
    return 16; // Mobile
  }

  double get _sectionSpacing {
    if (_isDesktop) return 32;
    if (_isTablet) return 24;
    return 16; // Mobile
  }

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    try {
      final openDepts = await _firestoreService.getDepartmentsForJobCards('open');
      final completedDepts = await _firestoreService.getDepartmentsForJobCards('completed');
      _departments = (openDepts + completedDepts).toSet().toList()..sort();
      setState(() {});
    } catch (e) {
      // silent fail - dashboard still works
    }
  }

  Future<void> _loadDashboardData([String? dept, DateTime? month]) async {
    print('Loading dashboard data with dept: $dept, month: $month');
    setState(() => _isLoading = true);

    try {
      final allJobs = await _firestoreService.getAllJobCardsFuture();
      DateTimeRange? range;
      if (month != null) {
        final start = DateTime(month.year, month.month, 1);
        final end = DateTime(month.year, month.month + 1, 1).subtract(const Duration(days: 1));
        range = DateTimeRange(start: start, end: end);
      }
      final filteredJobs = allJobs.where((job) {
        final deptMatch = dept == null || job.department == dept;
        final dateMatch = range == null ||
            (job.createdAt != null &&
                job.createdAt!.isAfter(range.start.subtract(const Duration(days: 1))) &&
                job.createdAt!.isBefore(range.end.add(const Duration(days: 1))));
        return deptMatch && dateMatch;
      }).toList();

      // Core KPIs
      _totalJobs = filteredJobs.length;
      _openJobsCount = filteredJobs.where((j) => j.status == JobStatus.open).length;
      _completed7Days = allJobs
          .where((j) =>
              j.status == JobStatus.completed &&
              j.completedAt != null &&
              j.completedAt!.isAfter(DateTime.now().subtract(const Duration(days: 7))))
          .length;
      _completed30Days = allJobs
          .where((j) =>
              j.status == JobStatus.completed &&
              j.completedAt != null &&
              j.completedAt!.isAfter(DateTime.now().subtract(const Duration(days: 30))))
          .length;

      // Completion rate (filtered period)
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

      // New KPI - Average Response Time (creation → assignment)
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

      // New KPI - Pending assignments
      _pendingAssignments = filteredJobs.where((j) => j.status == JobStatus.open && (j.assignedClockNos == null || j.assignedClockNos!.isEmpty)).length;

      // New KPI - Aged backlog (open jobs)
      final openJobs = filteredJobs.where((j) => j.status == JobStatus.open && j.createdAt != null).toList();
      _agedOpen7d = openJobs.where((j) => j.createdAt!.isBefore(DateTime.now().subtract(const Duration(days: 7)))).length;
      _agedOpen30d = openJobs.where((j) => j.createdAt!.isBefore(DateTime.now().subtract(const Duration(days: 30)))).length;

      // Employee performance
      _employeePerformance = {};
      for (var j in completedJobs) {
        if (j.completedBy != null) {
          _employeePerformance[j.completedBy!] = (_employeePerformance[j.completedBy!] ?? 0) + 1;
        }
      }

      // Priority breakdown (open + completed)
      _priorityBreakdown = {};
      for (var j in filteredJobs) {
        final key = j.status == JobStatus.open ? 'Open P${j.priority}' : 'Completed P${j.priority}';
        _priorityBreakdown[key] = (_priorityBreakdown[key] ?? 0) + 1;
      }

      // Type breakdown (dynamic from data)
      _typeBreakdown = {};
      for (var j in filteredJobs) {
        final key = j.status == JobStatus.open ? 'Open ${j.type.displayName}' : 'Completed ${j.type.displayName}';
        _typeBreakdown[key] = (_typeBreakdown[key] ?? 0) + 1;
      }

      // Machine breakdown (key for breakdown tracking)
      _machineBreakdown = {};
      for (var j in filteredJobs) {
        final key = j.machine?.trim().isNotEmpty == true ? j.machine! : 'Unknown Machine';
        _machineBreakdown[key] = (_machineBreakdown[key] ?? 0) + 1;
      }

      // Trend data
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      final createdPerDay = <DateTime, int>{};
      final completedPerDay = <DateTime, int>{};
      for (var job in allJobs) {
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

      setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading dashboard: $e'), backgroundColor: Colors.red),
        );
      }
      setState(() => _isLoading = false);
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
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Full Excel/PDF export coming in next release')),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadDashboardData(selectedDept, selectedMonth),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadDashboardData(selectedDept, selectedMonth),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(_screenPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Filters - more prominent with clear button always visible
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

                    // Key Metrics Cards - expanded for better analytics
                    _buildMetricsCards(),

                    SizedBox(height: _sectionSpacing),

                    // Analytics header
                    Text(
                      'Analytics & Breakdowns',
                      style: TextStyle(
                        fontSize: _isDesktop ? 26 : 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: _isDesktop ? 24 : 16),

                    // Charts - responsive grid on desktop, stacked on mobile/tablet
                    if (_isDesktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildPriorityChart()),
                          const SizedBox(width: 24),
                          Expanded(child: _buildTypeChart()),
                          const SizedBox(width: 24),
                          Expanded(child: _buildEmployeePerformanceChart()),
                        ],
                      )
                    else
                      Column(
                        children: [
                          _buildPriorityChart(),
                          SizedBox(height: _sectionSpacing),
                          _buildTypeChart(),
                          SizedBox(height: _sectionSpacing),
                          _buildEmployeePerformanceChart(),
                        ],
                      ),

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

  Widget _buildMetricsCards() {
    return GridView.count(
      crossAxisCount: _metricsCrossAxisCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: _isDesktop ? 20 : 16,
      mainAxisSpacing: _isDesktop ? 20 : 16,
      children: [
        _buildMetricCard('Total Jobs', _totalJobs.toString(), Icons.assignment, Colors.indigo),
        _buildMetricCard('Open Jobs', _openJobsCount.toString(), Icons.pending_actions, Colors.orange),
        _buildMetricCard('Completed (7d)', _completed7Days.toString(), Icons.check_circle_outline, Colors.green),
        _buildMetricCard('Completed (30d)', _completed30Days.toString(), Icons.timeline, Colors.blue),
        _buildMetricCard('Completion Rate', '${_completionRate.toStringAsFixed(0)}%', Icons.percent, Colors.teal),
        _buildMetricCard('Avg Completion (MTTR)', _averageCompletionTime != null ? _formatDuration(_averageCompletionTime!) : 'N/A', Icons.schedule, Colors.purple),
        _buildMetricCard('Avg Response Time', _avgResponseTime != null ? _formatDuration(_avgResponseTime!) : 'N/A', Icons.timer, Colors.amber),
        _buildMetricCard('Pending Assignments', _pendingAssignments.toString(), Icons.person_off, Colors.redAccent),
        _buildMetricCard('Aged Open (>7d)', _agedOpen7d.toString(), Icons.warning_amber, Colors.deepOrange),
        _buildMetricCard('Aged Open (>30d)', _agedOpen30d.toString(), Icons.dangerous, Colors.red),
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Card(
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
    );
  }

  Widget _buildPriorityChart() {
    final openPriorities = ['Open P1', 'Open P2', 'Open P3', 'Open P4', 'Open P5'];
    final completedPriorities = ['Completed P1', 'Completed P2', 'Completed P3', 'Completed P4', 'Completed P5'];

    final openData = openPriorities.map((key) => _priorityBreakdown[key] ?? 0).toList();
    final completedData = completedPriorities.map((key) => _priorityBreakdown[key] ?? 0).toList();

    final sections = <PieChartSectionData>[];
    final colors = [Colors.red, Colors.orange, Colors.green, Colors.blue, Colors.purple];
    // Open priorities
    for (int i = 0; i < openData.length; i++) {
      if (openData[i] > 0) {
        sections.add(PieChartSectionData(value: openData[i].toDouble(), color: colors[i], title: 'P${i+1} Open', radius: 55, titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)));
      }
    }
    // Completed priorities - darker tones
    for (int i = 0; i < completedData.length; i++) {
      if (completedData[i] > 0) {
        sections.add(PieChartSectionData(value: completedData[i].toDouble(), color: colors[i].shade700, title: 'P${i+1} Comp', radius: 55, titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)));
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
              height: 220,
              child: sections.isEmpty
                  ? const Center(child: Text('No data available'))
                  : PieChart(
                      PieChartData(
                        sections: sections,
                        centerSpaceRadius: 40,
                        sectionsSpace: 4,
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _buildLegendItem('P1 Open', Colors.red),
                _buildLegendItem('P2 Open', Colors.orange),
                _buildLegendItem('P3 Open', Colors.green),
                _buildLegendItem('P4 Open', Colors.blue),
                _buildLegendItem('P5 Open', Colors.purple),
                _buildLegendItem('P1 Comp', Colors.red.shade700),
                _buildLegendItem('P2 Comp', Colors.orange.shade700),
                _buildLegendItem('P3 Comp', Colors.green.shade700),
                _buildLegendItem('P4 Comp', Colors.blue.shade700),
                _buildLegendItem('P5 Comp', Colors.purple.shade700),
              ],
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
              height: 220,
              child: sections.isEmpty
                  ? const Center(child: Text('No data available'))
                  : PieChart(
                      PieChartData(
                        sections: sections,
                        centerSpaceRadius: 40,
                        sectionsSpace: 4,
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            const Text('Legend: Open vs Completed shown in labels', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
              height: 250,
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
    final topEmployees = sortedEmployees.take(3).toList(); // top 3

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
              height: 220,
              child: sections.isEmpty
                  ? const Center(child: Text('No data available'))
                  : PieChart(
                      PieChartData(
                        sections: sections,
                        centerSpaceRadius: 40,
                        sectionsSpace: 4,
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
              height: 250,
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
    return Row(
      children: [
        Container(width: 16, height: 16, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
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
                          bottom: BorderSide(color: index < jobCards.length - 1 ? Colors.grey.withOpacity(0.3) : Colors.transparent),
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
                                Text('${job.type.displayName} • ${job.machine ?? "—"} • ${job.operator}', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: job.status == JobStatus.open ? Colors.blue.withOpacity(0.15) : Colors.orange.withOpacity(0.15),
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
            const Expanded(child: Text('Job Card Details', style: TextStyle(fontSize: 20))),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Edit flow for ${jobCard.description} opened')));
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF8C42), foregroundColor: Colors.black),
            child: const Text('Edit Job'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 15)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toUpperCase()) {
      case 'P1':
        return Colors.red;
      case 'P2':
        return Colors.orange;
      case 'P3':
        return Colors.green;
      default:
        return Colors.grey;
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
          title: const Text('Select Month'),
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
                this.selectedMonth = DateTime(selectedYear, selectedMonthNum);
                _loadDashboardData(selectedDept, this.selectedMonth);
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
