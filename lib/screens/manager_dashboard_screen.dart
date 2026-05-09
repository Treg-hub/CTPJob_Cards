import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
    _loadDepartmentsFromFirestore();
  }

  Future<void> _loadDepartmentsFromFirestore() async {
    try {
      final jobsSnapshot = await FirebaseFirestore.instance
          .collection('job_cards')
          .get();

      final Set<String> departments = {};
      for (var doc in jobsSnapshot.docs) {
        final dept = doc.data()['department'] as String?;
        if (dept != null && dept.trim().isNotEmpty) {
          departments.add(dept.trim());
        }
      }

      final sortedList = departments.toList()..sort();
      setState(() {
        allDepartments = sortedList;
        if (currentEmployee?.department != null && sortedList.contains(currentEmployee!.department)) {
          selectedDepartments.add(currentEmployee!.department);
          showAllDepartments = false;
        }
      });
    } catch (e) {
      debugPrint('Error loading departments: $e');
    }
  }

  List<JobCard> _getFilteredJobs(List<JobCard> allJobs) {
    List<JobCard> filtered = allJobs;

    if (!showAllDepartments && selectedDepartments.isNotEmpty) {
      filtered = filtered.where((j) => 
        selectedDepartments.contains(j.department)
      ).toList();
    }

    final now = DateTime.now();
    if (dateRange == '7') {
      filtered = filtered.where((j) {
        final date = j.createdAt ?? j.lastUpdatedAt ?? now;
        return now.difference(date).inDays <= 7;
      }).toList();
    } else if (dateRange == '30') {
      filtered = filtered.where((j) {
        final date = j.createdAt ?? j.lastUpdatedAt ?? now;
        return now.difference(date).inDays <= 30;
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manager Dashboard'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadDepartmentsFromFirestore),
        ],
      ),
      body: StreamBuilder<List<JobCard>>(
        stream: _firestoreService.getAllJobCards(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final allJobs = snapshot.data!;
          final filteredJobs = _getFilteredJobs(allJobs);
          final openJobs = filteredJobs.where((j) => !j.isClosed).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
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
                _buildSmartDepartmentAreaChart(openJobs),
                const SizedBox(height: 24),
                _buildPriorityBreakdown(openJobs),
                const SizedBox(height: 24),
                _buildTechnicianLeaderboard(filteredJobs),
                const SizedBox(height: 40), // Extra space at bottom
              ],
            ),
          );
        },
      ),
    );
  }

  // ==================== KPI SECTION (FIXED) ====================
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
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
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
          const Text('Loading departments...', style: TextStyle(color: Colors.grey))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
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
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        const Text('Date Range: ', style: TextStyle(fontWeight: FontWeight.bold)),
        ChoiceChip(label: const Text('7 Days'), selected: dateRange == '7', onSelected: (_) => setState(() => dateRange = '7')),
        ChoiceChip(label: const Text('30 Days'), selected: dateRange == '30', onSelected: (_) => setState(() => dateRange = '30')),
        ChoiceChip(label: const Text('All Time'), selected: dateRange == 'all', onSelected: (_) => setState(() => dateRange = 'all')),
      ],
    );
  }

  // ==================== DYNAMIC TRENDLINE ====================
  Widget _buildTrendlineChart(List<JobCard> filteredJobs) {
    final Map<String, int> openByDay = {};
    final Map<String, int> closedByDay = {};

    for (final job in filteredJobs) {
      final date = job.createdAt ?? job.lastUpdatedAt ?? DateTime.now();
      final dayKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      if (!job.isClosed) {
        openByDay[dayKey] = (openByDay[dayKey] ?? 0) + 1;
      } else {
        closedByDay[dayKey] = (closedByDay[dayKey] ?? 0) + 1;
      }
    }

    final sortedDays = {...openByDay.keys, ...closedByDay.keys}.toList()..sort();

    if (sortedDays.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Open vs Closed Trend', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              SizedBox(height: 16),
              Text('No data available for the selected filters.', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    final maxValue = [
      ...openByDay.values,
      ...closedByDay.values,
      1,
    ].reduce((a, b) => a > b ? a : b);

    final openSpots = <FlSpot>[];
    final closedSpots = <FlSpot>[];

    for (int i = 0; i < sortedDays.length; i++) {
      final day = sortedDays[i];
      openSpots.add(FlSpot(i.toDouble(), (openByDay[day] ?? 0).toDouble()));
      closedSpots.add(FlSpot(i.toDouble(), (closedByDay[day] ?? 0).toDouble()));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Open vs Closed Trend (${dateRange == "7" ? "Last 7 Days" : dateRange == "30" ? "Last 30 Days" : "All Time"})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (sortedDays.length - 1).toDouble(),
                  minY: 0,
                  maxY: (maxValue + 1).toDouble(),
                  lineBarsData: [
                    LineChartBarData(spots: openSpots, isCurved: true, color: Colors.orange, barWidth: 3),
                    LineChartBarData(spots: closedSpots, isCurved: true, color: Colors.green, barWidth: 3),
                  ],
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt().clamp(0, sortedDays.length - 1);
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(sortedDays[index].substring(5), style: const TextStyle(fontSize: 10)),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true, interval: 1),
                    ),
                  ),
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: true),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildSmartDepartmentAreaChart(List<JobCard> openJobs) {
    if (openJobs.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Department Analytics', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              SizedBox(height: 16),
              Text('No open jobs available for the selected filters.', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    if (showAllDepartments || selectedDepartments.length != 1) {
      final Map<String, int> deptCount = {};
      for (final job in openJobs) {
        final dept = job.department;
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
                    sections: deptCount.entries.toList().asMap().entries.map((entry) {
                      final index = entry.key;
                      final deptEntry = entry.value;
                      return PieChartSectionData(
                        value: deptEntry.value.toDouble(),
                        title: '${deptEntry.key}\n${deptEntry.value}',
                        color: Colors.primaries[index % Colors.primaries.length],
                        radius: 90,
                        showTitle: true,
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      final selectedDept = selectedDepartments.first;
      final deptJobs = openJobs.where((j) => j.department == selectedDept).toList();

      if (deptJobs.isEmpty) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Open Jobs by Area in $selectedDept', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const Text('No open jobs found for this department.', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        );
      }

      final Map<String, int> areaCount = {};
      for (final job in deptJobs) {
        final area = job.area;
        areaCount[area] = (areaCount[area] ?? 0) + 1;
      }

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Open Jobs by Area in $selectedDept', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SizedBox(
                height: 220,
                child: PieChart(
                  PieChartData(
                    sections: areaCount.entries.toList().asMap().entries.map((entry) {
                      final index = entry.key;
                      final areaEntry = entry.value;
                      return PieChartSectionData(
                        value: areaEntry.value.toDouble(),
                        title: '${areaEntry.key}\n${areaEntry.value}',
                        color: Colors.primaries[index % Colors.primaries.length],
                        radius: 90,
                        showTitle: true,
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
  }
  Widget _buildPriorityBreakdown(List<JobCard> openJobs) {
    final Map<int, int> priorityCount = {};
    for (final job in openJobs) {
      priorityCount[job.priority] = (priorityCount[job.priority] ?? 0) + 1;
    }

    if (priorityCount.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Priority Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              SizedBox(height: 16),
              Text('No open jobs currently to display.', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Priority Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: priorityCount.values.reduce((a, b) => a > b ? a : b).toDouble() + 1,
                  barGroups: priorityCount.entries.map((entry) {
                    return BarChartGroupData(
                      x: entry.key,
                      barRods: [BarChartRodData(toY: entry.value.toDouble(), color: _getPriorityColor(entry.key))],
                    );
                  }).toList(),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (value, meta) {
                      return Text(value.toInt().toString(), style: const TextStyle(fontSize: 10));
                    })),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 1)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getPriorityColor(int priority) {
    switch (priority) {
      case 1: return Colors.green;
      case 2: return Colors.lightGreen;
      case 3: return Colors.amber;
      case 4: return Colors.deepOrange;
      case 5: return Colors.red;
      default: return Colors.grey;
    }
  }

  // ==================== TECHNICIAN LEADERBOARD (FIXED) ====================
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
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: top10.length,
                itemBuilder: (context, index) {
                  final tech = top10[index];
                  return ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(tech.key),
                    trailing: Text('${tech.value} jobs', style: const TextStyle(fontWeight: FontWeight.bold)),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}