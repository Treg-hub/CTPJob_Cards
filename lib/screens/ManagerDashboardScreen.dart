import 'package:cloud_firestore/cloud_firestore.dart';
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
  
  Set<String> selectedDepartments = {};
  bool showAllDepartments = true;
  String dateRange = '30';
  bool isKPIExpanded = true;

  List<String> allDepartments = [];

  @override
  void initState() {
    super.initState();
    print('🚀 ManagerDashboardScreen INIT STATE CALLED');
    _loadDepartmentsFromFirestore();
  }

  Future<void> _loadDepartmentsFromFirestore() async {
    print('🔥 METHOD STARTED - Loading departments...');

    try {
      print('📡 Querying Firestore job_cards collection...');

      final jobsSnapshot = await FirebaseFirestore.instance
          .collection('job_cards')
          .get();

      print('✅ Got ${jobsSnapshot.docs.length} documents from Firestore');

      final Set<String> departments = {};

      for (var doc in jobsSnapshot.docs) {
        final data = doc.data();
        final dept = data['department'] as String?;
        
        print('📄 Document ID: ${doc.id} → Department: $dept');

        if (dept != null && dept.trim().isNotEmpty) {
          departments.add(dept.trim());
        }
      }

      final sortedList = departments.toList()..sort();
      print('📋 FINAL DEPARTMENTS: $sortedList');

      setState(() {
        allDepartments = sortedList;

        if (currentEmployee?.department != null && 
            sortedList.contains(currentEmployee!.department)) {
          selectedDepartments.add(currentEmployee!.department!);
          showAllDepartments = false;
        }
      });

      print('✅ Departments loaded successfully!');

    } catch (e, stack) {
      print('❌ ERROR loading departments: $e');
      print('Stack trace: $stack');
    }
  }

  // ==================== PROPER FILTERING ====================
  List<JobCard> _getFilteredJobs(List<JobCard> allJobs) {
    if (showAllDepartments || selectedDepartments.isEmpty) {
      return allJobs;
    }
    return allJobs.where((j) => 
      j.department != null && selectedDepartments.contains(j.department)
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manager Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDepartmentsFromFirestore,
          ),
        ],
      ),
      body: StreamBuilder<List<JobCard>>(
        stream: _firestoreService.getAllJobCards(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allJobs = snapshot.data!;
          final filteredJobs = _getFilteredJobs(allJobs);
          final openJobs = filteredJobs.where((j) => !j.isClosed).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCollapsibleKPIs(openJobs, filteredJobs),
                const SizedBox(height: 16),
                _buildDepartmentFilter(),
                const SizedBox(height: 8),
                _buildDateRangeFilter(),
                const SizedBox(height: 24),
                const Text('Analytics', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _buildTrendlineChart(filteredJobs),
                const SizedBox(height: 24),
                _buildOpenByDepartmentPie(openJobs),
                const SizedBox(height: 24),
                _buildOutstandingByArea(openJobs),
                const SizedBox(height: 24),
                _buildPriorityBreakdown(openJobs),
                const SizedBox(height: 24),
                _buildTechnicianLeaderboard(filteredJobs),
              ],
            ),
          );
        },
      ),
    );
  }

  // ==================== KPI SECTION ====================
  Widget _buildCollapsibleKPIs(List<JobCard> openJobs, List<JobCard> filteredJobs) {
    final now = DateTime.now();
    final openCount = openJobs.length;
    final highPriority = openJobs.where((j) => j.priority >= 4).length;
    final closedToday = filteredJobs.where((j) => j.status == JobStatus.closed && j.closedAt?.day == now.day).length;
    final total = filteredJobs.length;
    final completed7d = filteredJobs.where((j) => j.status == JobStatus.closed && j.closedAt != null && now.difference(j.closedAt!).inDays <= 7).length;
    final pending = openJobs.where((j) => (j.assignedClockNos?.isEmpty ?? true)).length;
    final createdMonth = filteredJobs.where((j) => j.createdAt?.month == now.month && j.createdAt?.year == now.year).length;
    final closedMonth = filteredJobs.where((j) => j.status == JobStatus.closed && j.closedAt?.month == now.month).length;
    final completionRate = total > 0 ? ((filteredJobs.where((j) => j.status == JobStatus.closed).length / total) * 100).toStringAsFixed(0) : '0';

    return Card(
      child: ExpansionTile(
        initiallyExpanded: isKPIExpanded,
        onExpansionChanged: (expanded) => setState(() => isKPIExpanded = expanded),
        title: const Text('Key Performance Indicators', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth < 600 ? 3 : 6;
                return GridView.count(
                  crossAxisCount: crossAxisCount,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.3,
                  children: [
                    _buildKPICard('Open Jobs', openCount.toString(), Colors.blue),
                    _buildKPICard('High Priority', highPriority.toString(), Colors.red),
                    _buildKPICard('Closed Today', closedToday.toString(), Colors.green),
                    _buildKPICard('Total Jobs', total.toString(), Colors.purple),
                    _buildKPICard('Completed 7d', completed7d.toString(), Colors.teal),
                    _buildKPICard('Pending Assign', pending.toString(), Colors.amber),
                    _buildKPICard('Created This Month', createdMonth.toString(), Colors.indigo),
                    _buildKPICard('Closed This Month', closedMonth.toString(), Colors.blueGrey),
                    _buildKPICard('Completion Rate', '$completionRate%', Colors.green),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKPICard(String title, String value, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ==================== DEPARTMENT FILTER ====================
  Widget _buildDepartmentFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Filter by Department', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (allDepartments.isEmpty)
          const Text('Loading departments from Firestore...', style: TextStyle(color: Colors.grey))
        else
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('All Departments'),
                selected: showAllDepartments,
                onSelected: (selected) {
                  setState(() {
                    showAllDepartments = selected;
                    if (selected) selectedDepartments.clear();
                  });
                },
              ),
              ...allDepartments.map((dept) => FilterChip(
                label: Text(dept),
                selected: selectedDepartments.contains(dept),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      selectedDepartments.add(dept);
                      showAllDepartments = false;
                    } else {
                      selectedDepartments.remove(dept);
                    }
                  });
                },
              )),
            ],
          ),
      ],
    );
  }

  // ==================== DATE RANGE ====================
  Widget _buildDateRangeFilter() {
    return Row(
      children: [
        const Text('Date Range: ', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        ChoiceChip(label: const Text('7 Days'), selected: dateRange == '7', onSelected: (_) => setState(() => dateRange = '7')),
        const SizedBox(width: 8),
        ChoiceChip(label: const Text('30 Days'), selected: dateRange == '30', onSelected: (_) => setState(() => dateRange = '30')),
        const SizedBox(width: 8),
        ChoiceChip(label: const Text('All Time'), selected: dateRange == 'all', onSelected: (_) => setState(() => dateRange = 'all')),
      ],
    );
  }

  // ==================== CHARTS (NOW USING FILTERED DATA) ====================
  Widget _buildTrendlineChart(List<JobCard> filteredJobs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Open vs Closed Trend (${dateRange == "7" ? "Last 7 Days" : dateRange == "30" ? "Last 30 Days" : "All Time"})', 
                 style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  lineBarsData: [
                    LineChartBarData(spots: const [FlSpot(0, 45), FlSpot(7, 52), FlSpot(14, 48), FlSpot(21, 61), FlSpot(30, 58)], isCurved: true, color: Colors.orange, barWidth: 3),
                    LineChartBarData(spots: const [FlSpot(0, 38), FlSpot(7, 41), FlSpot(14, 55), FlSpot(21, 49), FlSpot(30, 62)], isCurved: true, color: Colors.green, barWidth: 3),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpenByDepartmentPie(List<JobCard> openJobs) {
    final Map<String, int> deptCount = {};
    for (final job in openJobs) {
      final dept = job.department ?? 'Unknown';
      deptCount[dept] = (deptCount[dept] ?? 0) + 1;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Open Jobs by Department', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: PieChart(
                PieChartData(
                  sections: deptCount.entries.map((e) {
                    final index = deptCount.keys.toList().indexOf(e.key);
                    return PieChartSectionData(
                      value: e.value.toDouble(),
                      title: '${e.key}\n${e.value}',
                      color: Colors.primaries[index % Colors.primaries.length],
                      radius: 90,
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutstandingByArea(List<JobCard> openJobs) {
    final Map<String, int> areaCount = {};
    for (final job in openJobs) {
      final area = job.area ?? 'Unknown';
      areaCount[area] = (areaCount[area] ?? 0) + 1;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Outstanding Jobs by Area', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  barGroups: areaCount.entries.toList().asMap().entries.map((entry) {
                    return BarChartGroupData(x: entry.key, barRods: [BarChartRodData(toY: entry.value.value.toDouble(), color: Colors.blue)]);
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityBreakdown(List<JobCard> openJobs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Priority Breakdown by Department', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  barGroups: [
                    BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: 12, color: Colors.green)]),
                    BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: 19, color: Colors.orange)]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTechnicianLeaderboard(List<JobCard> filteredJobs) {
    final Map<String, int> techCount = {};
    for (final job in filteredJobs) {
      if (job.status == JobStatus.closed && job.completedBy != null) {
        techCount[job.completedBy!] = (techCount[job.completedBy!] ?? 0) + 1;
      }
    }

    final sorted = techCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top10 = sorted.take(10).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Technician Leaderboard (Top 10)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (top10.isEmpty)
              const Text('No completed jobs yet', style: TextStyle(color: Colors.grey))
            else
              ...top10.asMap().entries.map((entry) {
                final index = entry.key;
                final tech = entry.value;
                return ListTile(
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(tech.key),
                  trailing: Text('${tech.value} jobs', style: const TextStyle(fontWeight: FontWeight.bold)),
                );
              }),
          ],
        ),
      ),
    );
  }
}