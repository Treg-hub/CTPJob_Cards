import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
import '../main.dart' show currentEmployee;
import '../widgets/ctp_app_bar.dart';
import '../widgets/job_card_tile.dart';
import 'job_card_detail_screen.dart';
import '../utils/screen_insets.dart';

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
      body: StreamBuilder<List<JobCard>>(
        // Newest 1500 jobs — covers the 7/30-day analytics windows without
        // streaming the entire collection history on every dashboard open.
        stream: _firestoreService.getAllJobCards(limit: 1500),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final allJobs = snapshot.data!;
          final filteredJobs = _getFilteredJobs(allJobs);
          final openJobs = filteredJobs.where((j) => !j.isClosed).toList();
          // Dept filter only — date range is intentionally excluded so the
          // 30-day open-count chart shows accurate historical stock levels.
          final deptFilteredJobs = (!showAllDepartments && selectedDepartments.isNotEmpty)
              ? allJobs.where((j) => selectedDepartments.contains(j.department)).toList()
              : allJobs;

          return Stack(
            children: [
              SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  56,
                  16,
                  ScreenInsets.scrollBottomFullScreen(context),
                ),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDepartmentFilter(),
                    const SizedBox(height: 8),
                    _buildDateRangeFilter(),
                    const SizedBox(height: 16),
                    _buildCollapsibleKPIs(openJobs, filteredJobs),
                    const SizedBox(height: 24),
                    const Text('Analytics', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    _buildOpenJobsByDayChart(deptFilteredJobs),
                    const SizedBox(height: 24),
                    _buildTrendlineChart(filteredJobs),
                    const SizedBox(height: 24),
                    _buildSmartDepartmentAreaChart(openJobs),
                    const SizedBox(height: 24),
                    _buildPriorityBreakdown(openJobs),
                    const SizedBox(height: 24),
                    _buildTeamPerformance(filteredJobs),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                    onPressed: _loadDepartmentsFromFirestore,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ==================== KPI SECTION ====================
  void _pushKPIList(String title, List<JobCard> jobs) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: CtpAppBar(title: title),
          body: jobs.isEmpty
              ? Center(
                  child: Text(
                    'No jobs match this filter',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: jobs.length,
                  itemBuilder: (ctx, i) => JobCardTile(
                    job: jobs[i],
                    onTap: () => Navigator.push(
                      ctx,
                      MaterialPageRoute(builder: (_) => JobCardDetailScreen(jobCard: jobs[i])),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildCollapsibleKPIs(List<JobCard> openJobs, List<JobCard> filteredJobs) {
    final now = DateTime.now();

    final highPriorityJobs   = openJobs.where((j) => j.priority >= 4).toList();
    final monitoringJobs     = filteredJobs.where((j) => j.status == JobStatus.monitor).toList();
    final closedTodayJobs    = filteredJobs.where((j) => j.status == JobStatus.closed && j.closedAt?.day == now.day && j.closedAt?.month == now.month).toList();
    final pendingJobs        = openJobs.where((j) => j.assignedClockNos?.isEmpty ?? true).toList();
    final overdue3dJobs      = openJobs.where((j) => j.createdAt != null && now.difference(j.createdAt!).inDays >= 3).toList();
    final overdue7dJobs      = openJobs.where((j) => j.createdAt != null && now.difference(j.createdAt!).inDays >= 7).toList();

    final total = filteredJobs.length;
    final completionRate = total > 0
        ? ((filteredJobs.where((j) => j.status == JobStatus.closed).length / total) * 100).toStringAsFixed(0)
        : '0';

    final closedWithTimes = filteredJobs.where((j) =>
        j.status == JobStatus.closed && j.createdAt != null && j.closedAt != null).toList();
    final avgResolutionHours = closedWithTimes.isEmpty
        ? null
        : closedWithTimes.map((j) => j.closedAt!.difference(j.createdAt!).inHours).reduce((a, b) => a + b) / closedWithTimes.length;
    final avgResolutionLabel = avgResolutionHours == null
        ? 'N/A'
        : avgResolutionHours < 24
            ? '${avgResolutionHours.toStringAsFixed(1)}h'
            : '${(avgResolutionHours / 24).toStringAsFixed(1)}d';

    return Card(
      child: ExpansionTile(
        initiallyExpanded: isKPIExpanded,
        onExpansionChanged: (expanded) => setState(() => isKPIExpanded = expanded),
        title: const Text('Key Performance Indicators', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth < 600 ? 3 : 6;
                return GridView.count(
                  crossAxisCount: crossAxisCount,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.25,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    _buildKPICard('Open Jobs',      openJobs.length.toString(),       Colors.blue,         onTap: () => _pushKPIList('Open Jobs', openJobs)),
                    _buildKPICard('High Priority',  highPriorityJobs.length.toString(), Colors.red,          onTap: () => _pushKPIList('High Priority (P4–P5)', highPriorityJobs)),
                    _buildKPICard('Monitoring',     monitoringJobs.length.toString(),  Colors.amber[700]!,  onTap: () => _pushKPIList('Monitoring', monitoringJobs)),
                    _buildKPICard('Closed Today',   closedTodayJobs.length.toString(), Colors.green,        onTap: () => _pushKPIList('Closed Today', closedTodayJobs)),
                    _buildKPICard('Pending Assign', pendingJobs.length.toString(),     Colors.orange,       onTap: () => _pushKPIList('Unassigned Jobs', pendingJobs)),
                    _buildKPICard('Avg Resolution', avgResolutionLabel,                Colors.teal),
                    _buildKPICard('Overdue >3d',    overdue3dJobs.length.toString(),   Colors.deepOrange,   onTap: () => _pushKPIList('Overdue (>3 days)', overdue3dJobs)),
                    _buildKPICard('Overdue >7d',    overdue7dJobs.length.toString(),   Colors.red[800]!,    onTap: () => _pushKPIList('Overdue (>7 days)', overdue7dJobs)),
                    _buildKPICard('Completion %',   '$completionRate%',                Colors.green[700]!),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKPICard(String title, String value, Color color, {VoidCallback? onTap}) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
              const SizedBox(height: 4),
              Text(title, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
              if (onTap != null) ...[
                const SizedBox(height: 2),
                Icon(Icons.arrow_forward_ios, size: 8, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ],
            ],
          ),
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
          Text('Loading departments...', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
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
            children: [
              const Text('Open vs Closed Trend', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text('No data available for the selected filters.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
            const SizedBox(height: 8),
            Row(
              children: [
                _legendDot(Colors.orange, 'Opened'),
                const SizedBox(width: 16),
                _legendDot(Colors.green, 'Closed'),
              ],
            ),
            const SizedBox(height: 12),
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
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: true, interval: 1),
                    ),
                  ),
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
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
            children: [
              const Text('Department Analytics', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text('No open jobs available for the selected filters.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                Text('No open jobs found for this department.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
            children: [
              const Text('Priority Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text('No open jobs currently to display.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                    bottomTitles: AxisTitles(sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (value, meta) {
                        const labels = {1: 'P1\nLow', 2: 'P2\nMed', 3: 'P3\nMid', 4: 'P4\nHigh', 5: 'P5\nCrit'};
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(labels[value.toInt()] ?? '', style: const TextStyle(fontSize: 9), textAlign: TextAlign.center),
                        );
                      },
                    )),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 1)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== TEAM PERFORMANCE ====================
  Widget _buildTeamPerformance(List<JobCard> filteredJobs) {
    final Map<String, _TechStats> stats = {};

    for (final job in filteredJobs) {
      // Closed count + avg resolution time
      if (job.status == JobStatus.closed && job.completedBy != null) {
        final name = job.completedBy!;
        stats.putIfAbsent(name, () => _TechStats(name));
        stats[name]!.closedCount++;
        if (job.createdAt != null && job.closedAt != null) {
          stats[name]!.totalResolutionHours += job.closedAt!.difference(job.createdAt!).inHours;
          stats[name]!.resolutionSamples++;
        }
      }
      // Currently assigned
      for (final name in (job.assignedNames ?? <String>[])) {
        if (!job.isClosed) {
          stats.putIfAbsent(name, () => _TechStats(name));
          stats[name]!.assignedCount++;
        }
      }
    }

    final rows = stats.values.toList()..sort((a, b) => b.closedCount.compareTo(a.closedCount));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Team Performance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              Text('No data yet', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
            else ...[
              // Header
              const Row(
                children: [
                  Expanded(flex: 3, child: Text('Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  Expanded(child: Text('Closed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
                  Expanded(child: Text('Avg Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
                  Expanded(child: Text('Assigned', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
                ],
              ),
              const Divider(),
              ...rows.map((t) {
                final avgHours = t.resolutionSamples > 0 ? t.totalResolutionHours / t.resolutionSamples : null;
                final avgLabel = avgHours == null
                    ? '—'
                    : avgHours < 24
                        ? '${avgHours.toStringAsFixed(1)}h'
                        : '${(avgHours / 24).toStringAsFixed(1)}d';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: Text(t.name, style: const TextStyle(fontSize: 13))),
                      Expanded(child: Text(t.closedCount.toString(), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
                      Expanded(child: Text(avgLabel, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
                      Expanded(child: Text(t.assignedCount.toString(), textAlign: TextAlign.center, style: TextStyle(color: t.assignedCount > 3 ? Colors.orange : null))),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  // ==================== OPEN JOBS BY DAY (last 30 days) ====================
  Widget _buildOpenJobsByDayChart(List<JobCard> allJobs) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final spots = <FlSpot>[];
    final labels = <String>[];

    for (int i = 29; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      final endOfDay = day.add(const Duration(days: 1));
      final count = allJobs.where((j) {
        final created = j.createdAt;
        if (created == null || created.isAfter(endOfDay)) return false;
        final closed = j.closedAt;
        return closed == null || closed.isAfter(endOfDay);
      }).length;
      spots.add(FlSpot((29 - i).toDouble(), count.toDouble()));
      labels.add('${day.day}/${day.month}');
    }

    final maxY = spots.map((s) => s.y).fold(0.0, (a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Open Job Cards — Last 30 Days', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Total open at end of each day', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: 29,
                  minY: 0,
                  maxY: (maxY + 2).toDouble(),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 3,
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.blue.withValues(alpha: 0.1),
                      ),
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 5,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt().clamp(0, 29);
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(labels[idx], style: const TextStyle(fontSize: 9)),
                          );
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 1)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: true),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== HELPERS ====================
  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
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
}

class _TechStats {
  final String name;
  int closedCount = 0;
  int assignedCount = 0;
  double totalResolutionHours = 0;
  int resolutionSamples = 0;
  _TechStats(this.name);
}