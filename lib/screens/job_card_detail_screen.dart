import 'package:flutter/material.dart';
import '../models/job_card.dart';

class JobCardDetailScreen extends StatelessWidget {
  final JobCard jobCard;

  const JobCardDetailScreen({super.key, required this.jobCard});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Job Card Details'),
        backgroundColor: const Color(0xFFFF8C42),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Job ID and Status
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Job ID: ${jobCard.id ?? 'N/A'}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: jobCard.status == JobStatus.completed ? Colors.green : Colors.blue,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            jobCard.status.displayName,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Priority: P${jobCard.priority}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: jobCard.priority >= 4 ? Colors.red : jobCard.priority == 3 ? Colors.orange : Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Location Information
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Location',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow('Department', jobCard.department),
                    _buildDetailRow('Area', jobCard.area),
                    _buildDetailRow('Machine', jobCard.machine),
                    _buildDetailRow('Part', jobCard.part),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Job Information
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Job Information',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow('Type', jobCard.type.displayName),
                    _buildDetailRow('Description', jobCard.description),
                    if (jobCard.notes.isNotEmpty) _buildDetailRow('Notes', jobCard.notes),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Personnel Information
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Personnel',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow('Created By', jobCard.operator),
                    if (jobCard.assignedToName != null)
                      _buildDetailRow('Assigned To', jobCard.assignedToName!),
                    if (jobCard.completedBy != null)
                      _buildDetailRow('Completed By', jobCard.completedBy!),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Timeline
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Timeline',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    if (jobCard.createdAt != null)
                      _buildDetailRow('Created', _formatDateTime(jobCard.createdAt!)),
                    if (jobCard.assignedAt != null)
                      _buildDetailRow('Assigned', _formatDateTime(jobCard.assignedAt!)),
                    if (jobCard.startedAt != null)
                      _buildDetailRow('Started', _formatDateTime(jobCard.startedAt!)),
                    if (jobCard.notificationReceivedAt != null)
                      _buildDetailRow('Notification Received', _formatDateTime(jobCard.notificationReceivedAt!)),
                    if (jobCard.completedAt != null)
                      _buildDetailRow('Completed', _formatDateTime(jobCard.completedAt!)),
                    if (jobCard.lastUpdatedAt != null)
                      _buildDetailRow('Last Updated', _formatDateTime(jobCard.lastUpdatedAt!)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}