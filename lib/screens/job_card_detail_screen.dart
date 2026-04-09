import 'package:flutter/material.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
import '../main.dart' show currentEmployee;

class JobCardDetailScreen extends StatefulWidget {
  final JobCard jobCard;

  const JobCardDetailScreen({super.key, required this.jobCard});

  @override
  State<JobCardDetailScreen> createState() => _JobCardDetailScreenState();
}

class _JobCardDetailScreenState extends State<JobCardDetailScreen> {
  late int _reoccurrenceCount;
  final TextEditingController _commentController = TextEditingController();
  final FirestoreService _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    _reoccurrenceCount = widget.jobCard.reoccurrenceCount;
  }

  bool get isManager => currentEmployee?.position.toLowerCase().contains('manager') ?? false;

  void _incrementCount() {
    setState(() => _reoccurrenceCount++);
    _updateJobCard();
  }

  void _decrementCount() {
    if (_reoccurrenceCount > 1) {
      setState(() => _reoccurrenceCount--);
      _updateJobCard();
    }
  }

  Future<void> _updateJobCard() async {
    try {
      await _firestoreService.updateJobCard(widget.jobCard.id!, widget.jobCard.copyWith(reoccurrenceCount: _reoccurrenceCount));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _appendComment() async {
    if (_commentController.text.trim().isEmpty) return;
    final now = DateTime.now();
    final user = currentEmployee?.name ?? 'User';
    final newComment = '\n\n[${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2,'0')}] $user: ${_commentController.text.trim()}';
    final updatedComments = widget.jobCard.comments + newComment;
    try {
      await _firestoreService.updateJobCard(widget.jobCard.id!, widget.jobCard.copyWith(comments: updatedComments));
      setState(() => _commentController.clear());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comment added!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding comment: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

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
                          'Job ID: ${widget.jobCard.id ?? 'N/A'}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: widget.jobCard.status == JobStatus.completed ? Colors.green : Colors.blue,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            widget.jobCard.status.displayName,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Priority: P${widget.jobCard.priority}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: widget.jobCard.priority >= 4 ? Colors.red : widget.jobCard.priority == 3 ? Colors.orange : Colors.green,
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
                    _buildDetailRow('Department', widget.jobCard.department),
                    _buildDetailRow('Area', widget.jobCard.area),
                    _buildDetailRow('Machine', widget.jobCard.machine),
                    _buildDetailRow('Part', widget.jobCard.part),
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
                    _buildDetailRow('Type', widget.jobCard.type.displayName),
                    _buildDetailRow('Description', widget.jobCard.description),
                    if (widget.jobCard.notes.isNotEmpty) _buildDetailRow('Notes', widget.jobCard.notes),
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
                     _buildDetailRow('Created By', widget.jobCard.operator),
                     if (widget.jobCard.assignedNames != null)
                       for (var name in widget.jobCard.assignedNames!)
                         _buildDetailRow('Assigned To', name),
                     if (widget.jobCard.completedBy != null)
                       _buildDetailRow('Completed By', widget.jobCard.completedBy!),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (widget.jobCard.isCompleted && !isManager) ...[
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'CLOSED - View & Comment Only (Managers can edit)',
                    style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Reoccurrence Count
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reoccurrence Count',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          color: widget.jobCard.isCompleted && !isManager ? Colors.grey : null,
                          onPressed: () {
                            if (widget.jobCard.isCompleted && !isManager) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Cannot edit closed job cards. Managers only.'), backgroundColor: Colors.orange),
                              );
                              return;
                            }
                            _decrementCount();
                          },
                        ),
                        Text(
                          '$_reoccurrenceCount',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          color: widget.jobCard.isCompleted && !isManager ? Colors.grey : null,
                          onPressed: () {
                            if (widget.jobCard.isCompleted && !isManager) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Cannot edit closed job cards. Managers only.'), backgroundColor: Colors.orange),
                              );
                              return;
                            }
                            _incrementCount();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Comments
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Comments',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    if (widget.jobCard.comments.isNotEmpty)
                      Text(widget.jobCard.comments),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _commentController,
                      decoration: const InputDecoration(
                        labelText: 'Add a comment',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _appendComment,
                      child: const Text('Append Comment'),
                    ),
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
                    if (widget.jobCard.createdAt != null)
                      _buildDetailRow('Created', _formatDateTime(widget.jobCard.createdAt!)),
                    if (widget.jobCard.assignedAt != null)
                      _buildDetailRow('Assigned', _formatDateTime(widget.jobCard.assignedAt!)),
                    if (widget.jobCard.startedAt != null)
                      _buildDetailRow('Started', _formatDateTime(widget.jobCard.startedAt!)),
                    if (widget.jobCard.notificationReceivedAt != null)
                      _buildDetailRow('Notification Received', _formatDateTime(widget.jobCard.notificationReceivedAt!)),
                    if (widget.jobCard.completedAt != null)
                      _buildDetailRow('Completed', _formatDateTime(widget.jobCard.completedAt!)),
                    if (widget.jobCard.lastUpdatedAt != null)
                      _buildDetailRow('Last Updated', _formatDateTime(widget.jobCard.lastUpdatedAt!)),
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