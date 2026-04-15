import 'package:flutter/material.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
import 'job_card_detail_screen.dart';

class MonitoringDashboardScreen extends StatelessWidget {
  const MonitoringDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
         appBar: AppBar(
           title: const Text('Monitoring Dashboard'),
           backgroundColor: const Color(0xFFFF8C42),
           bottom: const TabBar(
             labelColor: Colors.black,
             unselectedLabelColor: Colors.black87,
             tabs: [
               Tab(text: 'Active Monitoring'),
               Tab(text: 'Recently Auto-Closed'),
             ],
           ),
         ),
        body: const TabBarView(
          children: [
            ActiveMonitoringTab(),
            RecentlyAutoClosedTab(),
          ],
        ),
      ),
    );
  }
}

class ActiveMonitoringTab extends StatelessWidget {
  const ActiveMonitoringTab({super.key});

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();
    return StreamBuilder<List<JobCard>>(
      stream: firestoreService.getMonitoringJobCards(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final jobs = snapshot.data!
          ..sort((a, b) => (a.monitoringStartedAt ?? DateTime.now()).compareTo(b.monitoringStartedAt ?? DateTime.now()));
        if (jobs.isEmpty) {
          return const Center(child: Text('No jobs currently in monitoring', style: TextStyle(color: Colors.white70)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: jobs.length,
          itemBuilder: (context, index) {
            final job = jobs[index];
            final now = DateTime.now();
            final daysLeft = 7 - (job.monitoringStartedAt != null ? now.difference(job.monitoringStartedAt!).inDays : 0);
            final isOverdue = daysLeft <= 0;
            return Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                title: Text('Job #${job.jobCardNumber ?? job.id ?? 'N/A'}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.description, style: const TextStyle(color: Colors.white70), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isOverdue ? Colors.red.withValues(alpha: 51) : Colors.orange.withValues(alpha: 51),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isOverdue ? 'Overdue!' : '$daysLeft days left',
                        style: TextStyle(
                          color: isOverdue ? Colors.red : Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white70),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => JobCardDetailScreen(jobCard: job)),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class RecentlyAutoClosedTab extends StatelessWidget {
  const RecentlyAutoClosedTab({super.key});

  DateTime getStartDate() {
    final now = DateTime.now();
    // If Monday (weekday 1), start from Friday (subtract 3 days: Mon-Sun=1, Sat=2, Fri=3)
    if (now.weekday == 1) {
      return DateTime(now.year, now.month, now.day - 3);
    } else {
      // Otherwise, yesterday
      return DateTime(now.year, now.month, now.day - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();
    final startDate = getStartDate();
    return FutureBuilder<List<JobCard>>(
      future: firestoreService.getRecentlyAutoClosed(startDate),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final jobs = snapshot.data!
          ..sort((a, b) => (b.closedAt ?? DateTime.now()).compareTo(a.closedAt ?? DateTime.now()));
        if (jobs.isEmpty) {
          return Center(child: Text('No auto-closed jobs since ${startDate.day}/${startDate.month}/${startDate.year}', style: const TextStyle(color: Colors.white70)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: jobs.length,
          itemBuilder: (context, index) {
            final job = jobs[index];
            return Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                title: Text('Job #${job.jobCardNumber ?? job.id ?? 'N/A'}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.description, style: const TextStyle(color: Colors.white70), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(
                      'Auto-closed: ${job.closedAt != null ? '${job.closedAt!.day}/${job.closedAt!.month}/${job.closedAt!.year}' : 'Unknown'}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
                trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white70),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => JobCardDetailScreen(jobCard: job)),
                ),
              ),
            );
          },
        );
      },
    );
  }
}