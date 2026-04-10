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
      await _firestoreService.updateJobCard(
        widget.jobCard.id!,
        widget.jobCard.copyWith(reoccurrenceCount: _reoccurrenceCount),
      );
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
    final newComment = '\n\n[${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}] $user: ${_commentController.text.trim()}';
    final updatedComments = widget.jobCard.comments + newComment;
    try {
      await _firestoreService.updateJobCard(
        widget.jobCard.id!,
        widget.jobCard.copyWith(comments: updatedComments),
      );
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
        title: const Text('Job Card Details'),
        backgroundColor: const Color(0xFFFF8C42),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // Open comment input directly
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (context) => Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _commentController,
                    decoration: const InputDecoration(
                      labelText: 'Add comment...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _appendComment();
                        },
                        child: const Text('Add Comment'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
        icon: const Icon(Icons.comment),
        label: const Text('Add Comment'),
        backgroundColor: const Color(0xFFFF8C42),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Header
            Card(
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Job #${widget.jobCard.id ?? 'N/A'}',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: widget.jobCard.status == JobStatus.completed ? Colors.green : Colors.blue,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            widget.jobCard.status.displayName.toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(color: _getPriorityColor('P${widget.jobCard.priority}'), width: 2.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'P${widget.jobCard.priority}',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: _getPriorityColor('P${widget.jobCard.priority}'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            widget.jobCard.description,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Location
            _buildSectionCard(
              title: 'Location',
              child: Column(
                children: [
                  _buildDetailRow('Department', widget.jobCard.department ?? 'N/A'),
                  _buildDetailRow('Area', widget.jobCard.area ?? 'N/A'),
                  _buildDetailRow('Machine', widget.jobCard.machine ?? 'N/A'),
                  _buildDetailRow('Part', widget.jobCard.part ?? 'N/A'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Personnel
            _buildSectionCard(
              title: 'Personnel',
              child: Column(
                children: [
                  _buildDetailRow('Created By', widget.jobCard.operator ?? 'Unknown'),
                  if (widget.jobCard.assignedNames != null && widget.jobCard.assignedNames!.isNotEmpty)
                    _buildDetailRow('Assigned To', widget.jobCard.assignedNames!.join(', ')),
                  if (widget.jobCard.completedBy != null)
                    _buildDetailRow('Completed By', widget.jobCard.completedBy!),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Reoccurrence Count
            _buildSectionCard(
              title: 'Reoccurrence Count',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 32,
                    icon: const Icon(Icons.remove_circle_outline),
                    color: (widget.jobCard.isCompleted && !isManager) ? Colors.grey : const Color(0xFFFF8C42),
                    onPressed: (widget.jobCard.isCompleted && !isManager) ? null : _decrementCount,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$_reoccurrenceCount',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    iconSize: 32,
                    icon: const Icon(Icons.add_circle_outline),
                    color: (widget.jobCard.isCompleted && !isManager) ? Colors.grey : const Color(0xFFFF8C42),
                    onPressed: (widget.jobCard.isCompleted && !isManager) ? null : _incrementCount,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Comments
            _buildSectionCard(
              title: 'Comments',
              child: Column(
                children: [
                  if (widget.jobCard.comments.isNotEmpty) ...[
                    ..._parseComments(widget.jobCard.comments).map((comment) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(comment, style: const TextStyle(fontSize: 15)),
                      ),
                    )),
                  ] else
                    const Text('No comments yet', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 12),
                  // Comment input is now in the floating button (see FAB above)
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Timeline
            _buildSectionCard(
              title: 'Timeline',
              child: Column(
                children: [
                  if (widget.jobCard.createdAt != null)
                    _buildTimelineRow('Created', widget.jobCard.createdAt!),
                  if (widget.jobCard.assignedAt != null)
                    _buildTimelineRow('Assigned', widget.jobCard.assignedAt!),
                  if (widget.jobCard.startedAt != null)
                    _buildTimelineRow('Started', widget.jobCard.startedAt!),
                  if (widget.jobCard.notificationReceivedAt != null)
                    _buildTimelineRow('Notification Received', widget.jobCard.notificationReceivedAt!),
                  if (widget.jobCard.completedAt != null)
                    _buildTimelineRow('Completed', widget.jobCard.completedAt!),
                  if (widget.jobCard.lastUpdatedAt != null)
                    _buildTimelineRow('Last Updated', widget.jobCard.lastUpdatedAt!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.grey)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }

  Widget _buildTimelineRow(String label, DateTime dateTime) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.grey)),
          ),
          Expanded(
            child: Text(_formatDateTime(dateTime), style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  List<String> _parseComments(String comments) {
    return comments.split('\n\n').where((c) => c.trim().isNotEmpty).toList();
  }

  Color _getPriorityColor(String priority) {
    final num = int.tryParse(priority.substring(1)) ?? 0;
    switch (num) {
      case 1: return Colors.green[600]!;
      case 2: return Colors.lightGreen[500]!;
      case 3: return Colors.amber[600]!;
      case 4: return Colors.deepOrange[600]!;
      case 5: return const Color(0xFFFF3D00);
      default: return Colors.grey;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}