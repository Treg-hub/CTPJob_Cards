import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
import '../main.dart' show currentEmployee;

class ManagerDashboardScreen extends StatefulWidget {
  const ManagerDashboardScreen({super.key});

  @override
  State<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends State<ManagerDashboardScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  // Dashboard data
  int _openJobsCount = 0;
  int _completed7Days = 0;
  int _completed30Days = 0;
  Duration? _averageCompletionTime;
  Map<String, int> _employeePerformance = {};
  Map<String, int> _priorityBreakdown = {};
  Map<String, int> _typeBreakdown = {};

  bool _isLoading = true;

  // Responsive design helpers
  bool get _isMobile => MediaQuery.of(context).size.width < 600;
  bool get _isTablet => MediaQuery.of(context).size.width >= 600 && MediaQuery.of(context).size.width < 1200;
  bool get _isDesktop => MediaQuery.of(context).size.width >= 1200;

  int get _metricsCrossAxisCount {
    if (_isDesktop) return 4;
    if (_isTablet) return 3;
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
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _firestoreService.getOpenJobCardsCount(),
        _firestoreService.getCompletedJobCardsCountInPeriod(DateTime.now().subtract(const Duration(days: 7))),
        _firestoreService.getCompletedJobCardsCountInPeriod(DateTime.now().subtract(const Duration(days: 30))),
        _firestoreService.getAverageCompletionTime(),
        _firestoreService.getEmployeePerformance(),
        _firestoreService.getJobCardsByPriority(),
        _firestoreService.getJobCardsByType(),
      ]);

      setState(() {
        _openJobsCount = results[0] as int;
        _completed7Days = results[1] as int;
        _completed30Days = results[2] as int;
        _averageCompletionTime = results[3] as Duration?;
        _employeePerformance = results[4] as Map<String, int>;
        _priorityBreakdown = results[5] as Map<String, int>;
        _typeBreakdown = results[6] as Map<String, int>;
        _isLoading = false;
      });
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
        title: const Text('Manager Dashboard'),
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
            icon: const Icon(Icons.refresh),
            onPressed: _loadDashboardData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: SingleChildScrollView(
                padding: EdgeInsets.all(_screenPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Key Metrics Cards
                    _buildMetricsCards(),

                    SizedBox(height: _sectionSpacing),

                    // Charts Section
                    Text(
                      'Analytics',
                      style: TextStyle(
                        fontSize: _isDesktop ? 22 : 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    SizedBox(height: _isDesktop ? 20 : 16),

                    // Charts Row for larger screens
                    if (_isDesktop) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildPriorityChart()),
                          const SizedBox(width: 24),
                          Expanded(child: _buildTypeChart()),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildEmployeePerformanceChart(),
                    ] else ...[
                      // Stacked charts for mobile/tablet
                      _buildPriorityChart(),
                      SizedBox(height: _sectionSpacing),
                      _buildTypeChart(),
                      SizedBox(height: _sectionSpacing),
                      _buildEmployeePerformanceChart(),
                    ],

                    SizedBox(height: _sectionSpacing),

                    // Live Job Cards List
                    Text(
                      'Live Job Cards',
                      style: TextStyle(
                        fontSize: _isDesktop ? 22 : 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    SizedBox(height: _isDesktop ? 20 : 16),

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
        _buildMetricCard(
          'Open Jobs',
          _openJobsCount.toString(),
          Icons.pending_actions,
          Colors.orange,
        ),
        _buildMetricCard(
          'Completed (7 days)',
          _completed7Days.toString(),
          Icons.check_circle,
          Colors.green,
        ),
        _buildMetricCard(
          'Completed (30 days)',
          _completed30Days.toString(),
          Icons.timeline,
          Colors.blue,
        ),
        _buildMetricCard(
          'Avg Completion Time',
          _averageCompletionTime != null ? _formatDuration(_averageCompletionTime!) : 'N/A',
          Icons.schedule,
          Colors.purple,
        ),
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityChart() {
    final openPriorities = ['Open P1', 'Open P2', 'Open P3'];
    final completedPriorities = ['Completed P1', 'Completed P2', 'Completed P3'];

    final openData = openPriorities.map((key) => _priorityBreakdown[key] ?? 0).toList();
    final completedData = completedPriorities.map((key) => _priorityBreakdown[key] ?? 0).toList();

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Priority Breakdown',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: (openData + completedData).reduce((a, b) => a > b ? a : b).toDouble() + 5,
                  barGroups: List.generate(3, (index) {
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: openData[index].toDouble(),
                          color: Colors.orange,
                          width: 16,
                        ),
                        BarChartRodData(
                          toY: completedData[index].toDouble(),
                          color: Colors.green,
                          width: 16,
                        ),
                      ],
                    );
                  }),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Text('P${value.toInt() + 1}');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('Open', Colors.orange),
                const SizedBox(width: 16),
                _buildLegendItem('Completed', Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChart() {
    final types = ['Mechanical', 'Electrical', 'Mech/Elec (Unknown)'];
    final openTypes = types.map((type) => 'Open $type').toList();
    final completedTypes = types.map((type) => 'Completed $type').toList();

    final openData = openTypes.map((key) => _typeBreakdown[key] ?? 0).toList();
    final completedData = completedTypes.map((key) => _typeBreakdown[key] ?? 0).toList();

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Job Type Breakdown',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: (openData + completedData).reduce((a, b) => a > b ? a : b).toDouble() + 5,
                  barGroups: List.generate(types.length, (index) {
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: openData[index].toDouble(),
                          color: Colors.blue,
                          width: 16,
                        ),
                        BarChartRodData(
                          toY: completedData[index].toDouble(),
                          color: Colors.teal,
                          width: 16,
                        ),
                      ],
                    );
                  }),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            types[value.toInt()],
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('Open', Colors.blue),
                const SizedBox(width: 16),
                _buildLegendItem('Completed', Colors.teal),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeePerformanceChart() {
    if (_employeePerformance.isEmpty) {
      return const Card(
        elevation: 4,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text('No completed jobs data available'),
          ),
        ),
      );
    }

    final sortedEmployees = _employeePerformance.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topEmployees = sortedEmployees.take(5).toList();

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Employee Performance (Top 5)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: topEmployees.isNotEmpty
                      ? topEmployees.first.value.toDouble() + 2
                      : 10,
                  barGroups: List.generate(topEmployees.length, (index) {
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: topEmployees[index].value.toDouble(),
                          color: Colors.indigo,
                          width: 20,
                        ),
                      ],
                    );
                  }),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() < topEmployees.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                topEmployees[value.toInt()].key,
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          color: color,
        ),
        const SizedBox(width: 4),
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
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text('Error loading job cards: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Card(
            elevation: 4,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final jobCards = snapshot.data!
            .where((job) => job.status != JobStatus.completed)
            .take(10) // Limit to 10 most recent for dashboard
            .toList();

        if (jobCards.isEmpty) {
          return const Card(
            elevation: 4,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text('No active job cards', style: TextStyle(color: Colors.white70)),
              ),
            ),
          );
        }

        return Card(
          elevation: 4,
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFFF8C42),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.list_alt, color: Colors.black),
                    const SizedBox(width: 8),
                    Text(
                      'Recent Active Jobs (${jobCards.length})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),

              // Job Cards List
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: jobCards.length,
                itemBuilder: (context, index) {
                  final job = jobCards[index];
                  return InkWell(
                    onTap: () => _showJobCardDetails(job),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: index < jobCards.length - 1 ? Colors.grey.withOpacity(0.3) : Colors.transparent,
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Priority Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getPriorityColor('P${job.priority}'),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'P${job.priority}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                          const SizedBox(width: 12),

                          // Job Details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  job.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${job.type.displayName} • ${job.operator}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Status and Arrow
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: job.status == JobStatus.open ? Colors.blue.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  job.status.displayName,
                                  style: TextStyle(
                                    color: job.status == JobStatus.open ? Colors.blue : Colors.orange,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.chevron_right,
                                color: Colors.white70,
                                size: 20,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              // Footer with "View All" button
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        // Navigate to full job cards screen
                        Navigator.pushNamed(context, '/view_job_cards');
                      },
                      icon: const Icon(Icons.visibility, size: 16),
                      label: const Text('View All Job Cards'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFFF8C42),
                      ),
                    ),
                  ],
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getPriorityColor('P${jobCard.priority}'),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'P${jobCard.priority}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Job Card Details',
                style: const TextStyle(fontSize: 18),
              ),
            ),
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
              _buildDetailRow('Machine', jobCard.machine),
              _buildDetailRow('Part', jobCard.part),
              _buildDetailRow('Operator', jobCard.operator),
              if (jobCard.operatorClockNo != null)
                _buildDetailRow('Operator ID', jobCard.operatorClockNo!),
              if (jobCard.assignedClockNos?.isNotEmpty ?? false)
                _buildDetailRow('Assigned To', jobCard.assignedNames?.join(', ') ?? 'Unassigned'),
              if (jobCard.notes.isNotEmpty)
              _buildDetailRow('Notes', jobCard.notes),
              if (jobCard.createdAt != null)
                _buildDetailRow('Created', _formatDateTime(jobCard.createdAt!)),
              if (jobCard.assignedAt != null)
                _buildDetailRow('Assigned', _formatDateTime(jobCard.assignedAt!)),
              if (jobCard.startedAt != null)
                _buildDetailRow('Started', _formatDateTime(jobCard.startedAt!)),
              if (jobCard.lastUpdatedAt != null)
                _buildDetailRow('Last Updated', _formatDateTime(jobCard.lastUpdatedAt!)),
              if (jobCard.notificationReceivedAt != null)
                _buildDetailRow('Notification Read', _formatDateTime(jobCard.notificationReceivedAt!)),
              if (jobCard.completedAt != null)
                _buildDetailRow('Completed', _formatDateTime(jobCard.completedAt!)),
              if (jobCard.completedBy != null)
                _buildDetailRow('Completed By', jobCard.completedBy!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Could navigate to edit screen here
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Navigate to edit: ${jobCard.description}')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8C42),
              foregroundColor: Colors.black,
            ),
            child: const Text('Edit Job'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
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
}
