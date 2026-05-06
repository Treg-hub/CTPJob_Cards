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
  bool showAllDepartments = false;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    // Default to logged-in user's department
    if (currentEmployee?.department != null) {
      selectedDepartments.add(currentEmployee!.department!);
    }
  }

  Future<void> _refreshData() async {
    setState(() => isLoading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manager Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // KPI Cards - 2 Rows of 6
            _buildKPIRow1(),
            const SizedBox(height: 12),
            _buildKPIRow2(),
            
            const SizedBox(height: 24),
            
            // Department Filter (below KPIs)
            _buildDepartmentFilter(),
            
            const SizedBox(height: 24),
            
            // Charts Section
            const Text('Analytics', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            
            // 1. Open vs Closed Trendline
            _buildTrendlineChart(),
            
            const SizedBox(height: 24),
            
            // 2. Open Jobs by Department (Pie)
            _buildOpenByDepartmentPie(),
            
            const SizedBox(height: 24),
            
            // 3. Outstanding by Area
            _buildOutstandingByArea(),
            
            const SizedBox(height: 24),
            
            // 4. Priority Breakdown
            _buildPriorityBreakdown(),
            
            const SizedBox(height: 24),
            
            // Technician Leaderboard (Future Section)
            _buildTechnicianLeaderboard(),
          ],
        ),
      ),
    );
  }

  Widget _buildKPIRow1() {
    return Row(
      children: [
        Expanded(child: _buildKPICard('Open Jobs', '124', Colors.blue)),
        Expanded(child: _buildKPICard('High Priority', '31', Colors.red)),
        Expanded(child: _buildKPICard('Closed Today', '18', Colors.green)),
        Expanded(child: _buildKPICard('Avg Resolution', '2.4d', Colors.orange)),
        Expanded(child: _buildKPICard('Total Jobs', '892', Colors.purple)),
        Expanded(child: _buildKPICard('Completed 7d', '67', Colors.teal)),
      ],
    );
  }

  Widget _buildKPIRow2() {
    return Row(
      children: [
        Expanded(child: _buildKPICard('Pending Assign', '45', Colors.amber)),
        Expanded(child: _buildKPICard('Created This Month', '156', Colors.indigo)),
        Expanded(child: _buildKPICard('Completion Rate', '87%', Colors.green)),
        Expanded(child: _buildKPICard('Closed This Month', '203', Colors.blueGrey)),
        Expanded(child: _buildKPICard('Avg Completion', '3.1d', Colors.cyan)),
        Expanded(child: _buildKPICard('Avg Response', '4.2h', Colors.pink)),
      ],
    );
  }

  Widget _buildKPICard(String title, String value, Color color) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildDepartmentFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Filter by Department', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
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
            // Add department chips here dynamically from Firestore later
          ],
        ),
      ],
    );
  }

  Widget _buildTrendlineChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Open vs Closed Trend (Last 30 Days)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  lineBarsData: [
                    LineChartBarData(
                      spots: const [FlSpot(0, 45), FlSpot(7, 52), FlSpot(14, 48), FlSpot(21, 61), FlSpot(30, 58)],
                      isCurved: true,
                      color: Colors.orange,
                      barWidth: 3,
                    ),
                    LineChartBarData(
                      spots: const [FlSpot(0, 38), FlSpot(7, 41), FlSpot(14, 55), FlSpot(21, 49), FlSpot(30, 62)],
                      isCurved: true,
                      color: Colors.green,
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

  Widget _buildOpenByDepartmentPie() {
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
                  sections: [
                    PieChartSectionData(value: 45, title: 'Mechanical\n45', color: Colors.blue, radius: 90),
                    PieChartSectionData(value: 32, title: 'Electrical\n32', color: Colors.orange, radius: 90),
                    PieChartSectionData(value: 28, title: 'General\n28', color: Colors.green, radius: 90),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutstandingByArea() {
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
                  barGroups: [
                    BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: 28, color: Colors.blue)]),
                    BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: 19, color: Colors.orange)]),
                    BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: 34, color: Colors.green)]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityBreakdown() {
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
                    BarChartGroupData(x: 0, barRods: [
                      BarChartRodData(toY: 12, color: Colors.green),
                      BarChartRodData(toY: 8, color: Colors.orange),
                    ]),
                    BarChartGroupData(x: 1, barRods: [
                      BarChartRodData(toY: 19, color: Colors.green),
                      BarChartRodData(toY: 14, color: Colors.orange),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTechnicianLeaderboard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Technician Leaderboard (Top Performers)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('Coming soon - Will show top technicians based on completed jobs', 
              style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }
}