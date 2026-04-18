import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/skeleton_loader.dart';
import '../models/employee.dart';
import '../models/job_card.dart';
import '../models/assignment_event.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../main.dart' show currentEmployee;

class JobCardDetailScreen extends StatefulWidget {
  final JobCard jobCard;

  const JobCardDetailScreen({super.key, required this.jobCard});

  @override
  State<JobCardDetailScreen> createState() => _JobCardDetailScreenState();
}

class _JobCardDetailScreenState extends State<JobCardDetailScreen> {
  late int _reoccurrenceCount;
  late JobCard _currentJobCard;
  final TextEditingController _commentController = TextEditingController();
  final FirestoreService _firestoreService = FirestoreService();
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _reoccurrenceCount = widget.jobCard.reoccurrenceCount;
    _currentJobCard = widget.jobCard;
  }

  bool get isManager => (currentEmployee?.position ?? '').toLowerCase().contains('manager');
  bool get isTech => (currentEmployee?.position ?? '').toLowerCase().contains('technician') || (currentEmployee?.position ?? '').toLowerCase().contains('tech');
  bool get _canAddNotes => isManager || (currentEmployee?.position ?? '').toLowerCase().contains('electrical') || (currentEmployee?.position ?? '').toLowerCase().contains('mechanical');
  bool get _canAddComments => !(currentEmployee?.position ?? '').toLowerCase().contains('electrical') && !(currentEmployee?.position ?? '').toLowerCase().contains('mechanical');

  Future<void> _appendComment() async {
    if (_commentController.text.trim().isEmpty) return;
    final now = DateTime.now();
    final user = currentEmployee?.name ?? 'User';
    final newComment = '\n\n[${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}] $user: ${_commentController.text.trim()}';
    final updatedComments = _currentJobCard.comments + newComment;

    try {
      await _firestoreService.saveJobCardOfflineAware(_currentJobCard.copyWith(
        comments: updatedComments,
        reoccurrenceCount: _reoccurrenceCount,
      ));
      setState(() => _commentController.clear());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Comment added!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding comment: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _selfAssign(JobCard jobCard) async {
    final current = currentEmployee;
    if (current == null) return;
    final updated = jobCard.copyWith(
      assignedClockNos: [...?jobCard.assignedClockNos, current.clockNo],
      assignedNames: [...?jobCard.assignedNames, current.name],
      assignedAt: DateTime.now(),
      notes: jobCard.notes,
    );
    final event = AssignmentEvent(
      assignedByName: current.name,
      assignedByClockNo: current.clockNo,
      assigneeClockNos: updated.assignedClockNos ?? [],
      assigneeNames: updated.assignedNames ?? [],
      timestamp: DateTime.now(),
    );
    final newHistory = List<AssignmentEvent>.from(_currentJobCard.assignmentHistory ?? []);
    newHistory.add(event);
    final finalUpdated = updated.copyWith(
      assignmentHistory: newHistory,
      assignedAt: newHistory.isNotEmpty ? newHistory.first.timestamp : DateTime.now(),
    );
    try {
      await _firestoreService.saveJobCardOfflineAware(finalUpdated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Assigned to you')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error assigning: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _selfUnassign(JobCard jobCard) async {
    final current = currentEmployee;
    if (current == null) return;
    final updated = jobCard.copyWith(
      assignedClockNos: jobCard.assignedClockNos?.where((c) => c != current.clockNo).toList(),
      assignedNames: jobCard.assignedNames?.where((n) => n != current.name).toList(),
    );
    final event = AssignmentEvent(
      assignedByName: current.name,
      assignedByClockNo: current.clockNo,
      assigneeClockNos: [current.clockNo],
      assigneeNames: [current.name],
      timestamp: DateTime.now(),
      isUnassign: true,
    );
    final newHistory = List<AssignmentEvent>.from(_currentJobCard.assignmentHistory ?? []);
    newHistory.add(event);
    final finalUpdated = updated.copyWith(assignmentHistory: newHistory);
    try {
      await _firestoreService.saveJobCardOfflineAware(finalUpdated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Removed from job')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error unassigning: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ==================== IMPROVED & COMPACT ASSIGN DIALOG ====================
  void _showAssignCompleteDialog(BuildContext context, JobCard job) {
    String searchQuery = '';
    List<String> selectedClockNos = [];
    List<String> selectedNames = [];
    bool isSaving = false;
  Timer? debounceTimer;

    selectedClockNos.addAll(job.assignedClockNos ?? []);
    selectedNames.addAll(job.assignedNames ?? []);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.95,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: StatefulBuilder(
          builder: (context, setDialogState) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text('Assign to Employees', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                // Search + Clear All
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Search employee...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        ),
                        onChanged: (value) {
                          debounceTimer?.cancel();
                          debounceTimer = Timer(const Duration(milliseconds: 300), () => setDialogState(() => searchQuery = value.toLowerCase()));
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => setDialogState(() {
                        selectedClockNos.clear();
                        selectedNames.clear();
                      }),
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Clear All'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Selected chips
                if (selectedClockNos.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: selectedClockNos.map((clockNo) {
                        final name = selectedNames[selectedClockNos.indexOf(clockNo)];
                        return Chip(
                          label: Text(name, style: const TextStyle(fontSize: 12)),
                          onDeleted: () => setDialogState(() {
                            selectedClockNos.remove(clockNo);
                            selectedNames.remove(name);
                          }),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        );
                      }).toList(),
                    ),
                  ),
                const SizedBox(height: 8),



                // Employee list grouped by department
                Expanded(
                  child: StreamBuilder<List<Employee>>(
                    stream: _firestoreService.getEmployeesStream(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      var employees = snapshot.data!;

                      if (searchQuery.isNotEmpty) {
                        employees = employees.where((e) => e.displayName.toLowerCase().contains(searchQuery)).toList();
                      }

                      // Sort by onsite first
                      employees.sort((a, b) => (a.isOnSite ? 0 : 1).compareTo(b.isOnSite ? 0 : 1));

                      // Group by department
                      final Map<String, List<Employee>> grouped = {};
                      for (final emp in employees) {
                        final dept = emp.department ?? 'No Department';
                        grouped.putIfAbsent(dept, () => []).add(emp);
                      }

                      if (employees.isEmpty) {
                        return const Center(child: Text('No employees match filters', style: TextStyle(color: Colors.white70, fontSize: 14)));
                      }

                      return ListView(
                        children: grouped.entries.map((entry) {
                          return ExpansionTile(
                            title: Text('${entry.key} (${entry.value.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            children: entry.value.expand((emp) {
                              final isSelected = selectedClockNos.contains(emp.clockNo);
                              return [
                                CheckboxListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
                                  visualDensity: VisualDensity.compact,
                                  title: Text(
                                    '${emp.name} - ${emp.position ?? ''} (${emp.department ?? ''})',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                  ),
                                  secondary: Icon(
                                    emp.isOnSite ? Icons.location_on : Icons.location_off,
                                    color: emp.isOnSite ? Colors.green : Colors.red[400]!,
                                    size: 16,
                                  ),
                                  tileColor: emp.isOnSite ? Colors.green.withValues(alpha: 20) : Colors.red.withValues(alpha: 20),
                                  value: isSelected,
                                  onChanged: (val) {
                                    setDialogState(() {
                                      if (val == true) {
                                        selectedClockNos.add(emp.clockNo);
                                        selectedNames.add(emp.name);
                                      } else {
                                        selectedClockNos.remove(emp.clockNo);
                                        selectedNames.remove(emp.name);
                                      }
                                    });
                                  },
                                ),
                              ];
                            }).toList()..removeLast(),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: isSaving || selectedClockNos.isEmpty
                          ? null
                          : () async {
                              setDialogState(() => isSaving = true);
                              try {
                                for (var clockNo in selectedClockNos) {
                                  final emp = await _firestoreService.getEmployee(clockNo);
                                  if (emp != null && !emp.isOnSite && context.mounted) {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Employee is OFF SITE'),
                                        content: Text('${emp.name} is currently OFF SITE.\n\nDo you still want to assign the job?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, Assign Anyway')),
                                        ],
                                      ),
                                    );
                                    if (confirm != true) {
                                      setDialogState(() => isSaving = false);
                                      return;
                                    }
                                  }
                                }

                                final updatedJob = job.copyWith(
                                  assignedClockNos: selectedClockNos,
                                  assignedNames: selectedNames,
                                  assignedAt: DateTime.now(),
                                  notes: job.notes,
                                );

                                final event = AssignmentEvent(
                                  assignedByName: currentEmployee?.name ?? 'Unknown',
                                  assignedByClockNo: currentEmployee?.clockNo ?? '',
                                  assigneeClockNos: selectedClockNos,
                                  assigneeNames: selectedNames,
                                  timestamp: DateTime.now(),
                                );
                                final newHistory = List<AssignmentEvent>.from(job.assignmentHistory ?? []);
                                newHistory.add(event);
                                final finalUpdatedJob = updatedJob.copyWith(
                                  assignmentHistory: newHistory,
                                  assignedAt: newHistory.isNotEmpty ? newHistory.first.timestamp : DateTime.now(),
                                );

      await _firestoreService.saveJobCardOfflineAware(finalUpdatedJob);

                                // Send notifications only for newly added employees
                                final newEmployees = selectedClockNos.where((clockNo) => !(job.assignedClockNos?.contains(clockNo) ?? false)).toList();
                                for (var i = 0; i < newEmployees.length; i++) {
                                  final clockNo = newEmployees[i];
                                  final emp = await _firestoreService.getEmployee(clockNo);
                                  if (emp?.fcmToken != null) {
                                     try {
                                       await _notificationService.sendJobAssignmentNotification(
                                         recipientToken: emp!.fcmToken!,
                                         jobCardId: job.id!,
                                         jobCardNumber: job.jobCardNumber,
                                         operator: currentEmployee?.name ?? 'Unknown',
                                         creator: job.operator ?? 'Unknown',
                                         department: emp.department,
                                         area: job.area,
                                         machine: job.machine,
                                         part: job.part,
                                         description: job.description,
                                       );
                                    } catch (e) {
                                      debugPrint('Notification failed for ${emp?.name ?? 'Unknown'}: $e');
                                    }
                                  }
                                }

                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Job assigned!')));
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                                  );
                                }
                              } finally {
                                if (context.mounted) setDialogState(() => isSaving = false);
                              }
                            },
                      child: isSaving
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Assign'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddCommentDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
          decoration: const BoxDecoration(
            color: Color(0xFF1F1F1F),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
          ),
          child: StatefulBuilder(
            builder: (context, setDialogState) => Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Add Comment & Update Reoccurrence', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(iconSize: 32, icon: const Icon(Icons.remove_circle_outline), color: const Color(0xFFFF8C42), onPressed: () { if (_reoccurrenceCount > 1) setDialogState(() => _reoccurrenceCount--); }),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8), decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(12)), child: Text('$_reoccurrenceCount', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white))),
                      IconButton(iconSize: 32, icon: const Icon(Icons.add_circle_outline), color: const Color(0xFFFF8C42), onPressed: () => setDialogState(() => _reoccurrenceCount++)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(controller: _commentController, decoration: const InputDecoration(labelText: 'Comment / Work Done', border: OutlineInputBorder(), labelStyle: TextStyle(color: Colors.white70)), maxLines: 4, style: const TextStyle(color: Colors.white)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
                      const SizedBox(width: 12),
                      ElevatedButton(onPressed: () { Navigator.pop(context); _appendComment(); }, child: const Text('Save Comment')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showAddNoteDialog() {
    final noteController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
          decoration: const BoxDecoration(
            color: Color(0xFF1F1F1F),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Add Note', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 20),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'Note / Work Progress',
                    border: OutlineInputBorder(),
                    labelStyle: TextStyle(color: Colors.white70)
                  ),
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white)
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
                    const SizedBox(width: 12),
                    ElevatedButton(onPressed: () { Navigator.pop(context); _appendNote(noteController.text.trim()); }, child: const Text('Save Note')),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _appendNote(String noteText) async {
    if (noteText.isEmpty) return;
    final now = DateTime.now();
    final user = currentEmployee?.name ?? 'User';
    final newNote = '\n\n[${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}] $user: $noteText';
    final updatedNotes = _currentJobCard.notes + newNote;

    try {
      await _firestoreService.saveJobCardOfflineAware(_currentJobCard.copyWith(notes: updatedNotes));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note added!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding note: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _addPhoto(JobCard jobCard, String section) async {
    final picker = ImagePicker();
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Photo Source'),
        content: const Text('Choose where to get the photo from.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.camera),
            child: const Text('Camera'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            child: const Text('Gallery'),
          ),
        ],
      ),
    );

    if (source == null) return;

    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile == null) return;

    // Compress the image
    final compressedFile = await FlutterImageCompress.compressAndGetFile(
      pickedFile.path,
      '${pickedFile.path}_compressed.jpg',
      minWidth: 800,
      minHeight: 800,
      quality: 85,
    );

    if (compressedFile == null) return;

    // Upload to Firebase Storage
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('job_cards/${jobCard.id}/photos/$timestamp.jpg');

    try {
      final uploadTask = storageRef.putFile(File(compressedFile.path));
      final snapshot = await uploadTask.whenComplete(() {});
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Update job card with new photo
      final photoMap = {
        'section': section,
        'url': downloadUrl,
        'addedBy': currentEmployee?.name ?? 'Unknown',
        'timestamp': DateTime.now().toIso8601String(),
      };
      final updatedPhotos = [...jobCard.photos, photoMap];
      await _firestoreService.saveJobCardOfflineAware(
        jobCard.copyWith(photos: updatedPhotos),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo added!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading photo: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

    void _showPhotoDialog(String photoUrl, String addedBy, String timestamp) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CachedNetworkImage(
              imageUrl: photoUrl,                    // ← fixed: use the parameter, not job.photoUrl
              fit: BoxFit.cover,
              placeholder: (context, url) => const SkeletonLoader(height: 200),
              errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.red),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Added by $addedBy on ${DateTime.parse(timestamp).toLocal().toString().substring(0,16)}',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const double sectionSpacing = 5.0;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Job Card Details'),
          backgroundColor: const Color(0xFFFF8C42),
          bottom: const TabBar(
            labelColor: Colors.black,
            unselectedLabelColor: Colors.black54,
            tabs: [
              Tab(text: 'Details'),
              Tab(text: 'Photos'),
            ],
          ),
        ),
        body: StreamBuilder<JobCard>(
          stream: _firestoreService.getJobCardStream(widget.jobCard.id!),
          builder: (context, snapshot) {
            final jobCard = snapshot.hasData ? snapshot.data! : widget.jobCard;
            _currentJobCard = jobCard;
            return TabBarView(
              children: [
                // Details Tab
                SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeroHeader(jobCard),
                      SizedBox(height: sectionSpacing),
                      _buildAssignmentButtons(jobCard),
                      SizedBox(height: sectionSpacing),
                      _buildCombinedCard(jobCard),
                      SizedBox(height: sectionSpacing),
                      _buildDetailsCard(jobCard),
                      SizedBox(height: sectionSpacing),
                      _buildActivityLogCard(jobCard),
                      SizedBox(height: sectionSpacing),
                      _buildAssignmentLogCard(jobCard),
                    ],
                  ),
                ),
                // Photos Tab
                SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Photos', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                          TextButton.icon(
                            onPressed: () => _addPhoto(jobCard, 'photos'),
                            icon: const Icon(Icons.camera_alt, size: 20),
                            label: const Text('Add Photo'),
                            style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF8C42)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...['description', 'comments', 'notes', 'photos'].map((section) {
                        final sectionPhotos = jobCard.photos.where((p) => p['section'] == section).toList();
                        if (sectionPhotos.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(section.toUpperCase(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)),
                            const SizedBox(height: 6),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                              itemCount: sectionPhotos.length,
                              itemBuilder: (context, index) {
                                final photoMap = sectionPhotos[index];
                                final photoUrl = photoMap['url'];
                                final addedBy = photoMap['addedBy'];
                                final timestamp = photoMap['timestamp'];
                                return GestureDetector(
                                  onTap: () => _showPhotoDialog(photoUrl, addedBy, timestamp),
                                  child: Stack(
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(8),
                                          image: DecorationImage(
                                            image: NetworkImage(photoUrl),
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 0,
                                        left: 0,
                                        right: 0,
                                        child: Container(
                                          color: Colors.black54,
                                          padding: const EdgeInsets.all(4),
                                          child: Text(
                                            'By $addedBy\n${DateTime.parse(timestamp).toLocal().toString().substring(0,16)}',
                                            style: const TextStyle(color: Colors.white, fontSize: 10),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                          ],
                        );
                      }),
                      if (jobCard.photos.isEmpty)
                        const Text('No photos', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        bottomNavigationBar: _buildBottomBanner(_currentJobCard),
      ),
    );
  }

  Widget _buildBottomBanner(JobCard jobCard) {
    // Hide all buttons if job is closed
    if (jobCard.status == JobStatus.closed) return const SizedBox.shrink();

    final isAssigned = jobCard.assignedClockNos?.contains(currentEmployee?.clockNo ?? '') ?? false;
    if (!isAssigned && !isManager) return const SizedBox.shrink();

    final buttons = <Widget>[];

    if (jobCard.status == JobStatus.open) {
      if (jobCard.startedAt == null) {
        buttons.add(
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _startJob(jobCard),
              icon: const Icon(Icons.play_arrow, size: 20),
              label: const Text('Start', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        );
      }
      buttons.add(
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _showCompleteDialog(jobCard),
            icon: const Icon(Icons.check_circle, size: 20),
            label: const Text('Complete', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
          ),
        ),
      );
      buttons.add(
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _showMonitorDialog(jobCard),
            icon: const Icon(Icons.visibility, size: 20),
            label: const Text('Monitor', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      );
    } else if (jobCard.status == JobStatus.monitor) {
      buttons.add(
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _showAdjustmentDialog(jobCard),
            icon: const Icon(Icons.refresh, size: 20),
            label: const Text('Adjustment Made', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      );
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1F1F1F),
        border: Border(top: BorderSide(color: Colors.white24)),
      ),
      child: Row(
        children: buttons.map((btn) => [btn, const SizedBox(width: 8)]).expand((x) => x).toList()..removeLast(),
      ),
    );
  }



  Future<void> _startJob(JobCard jobCard) async {
    final now = DateTime.now();
    final user = currentEmployee?.name ?? 'User';
    final note = '\n\n[${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}] Started by $user';
    final updated = jobCard.copyWith(
      startedAt: now,
      notes: jobCard.notes + note,
    );
    final event = AssignmentEvent(
      assignedByName: 'Started by $user',
      assignedByClockNo: currentEmployee?.clockNo ?? '',
      assigneeClockNos: [],
      assigneeNames: [],
      timestamp: now,
    );
    final newHistory = List<AssignmentEvent>.from(jobCard.assignmentHistory ?? []);
    newHistory.add(event);
    final finalUpdated = updated.copyWith(assignmentHistory: newHistory);
    try {
      await _firestoreService.saveJobCardOfflineAware(finalUpdated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Job started!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting job: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showCompleteDialog(JobCard jobCard) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Job'),
        content: TextField(
          controller: noteController,
          decoration: const InputDecoration(labelText: 'Description/Corrective Action Taken'),
          maxLines: 4,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final note = noteController.text.trim();
              if (note.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a description'), backgroundColor: Colors.red));
                return;
              }
              Navigator.pop(context);
              await _completeJob(jobCard, false, note);
            },
            child: const Text('Complete'),
          ),
        ],
      ),
    );
  }

  void _showMonitorDialog(JobCard jobCard) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start Monitoring'),
        content: TextField(
          controller: noteController,
          decoration: const InputDecoration(labelText: 'Description/Corrective Action Taken'),
          maxLines: 4,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final note = noteController.text.trim();
              if (note.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a description'), backgroundColor: Colors.red));
                return;
              }
              Navigator.pop(context);
              await _completeJob(jobCard, true, note);
            },
            child: const Text('Start Monitoring'),
          ),
        ],
      ),
    );
  }

  void _showAdjustmentDialog(JobCard jobCard) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adjustment Made'),
        content: TextField(
          controller: noteController,
          decoration: const InputDecoration(labelText: 'Description of Adjustment'),
          maxLines: 4,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final note = noteController.text.trim();
              if (note.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a description'), backgroundColor: Colors.red));
                return;
              }
              Navigator.pop(context);
              await _adjustmentMade(jobCard, note);
            },
            child: const Text('Save Adjustment'),
          ),
        ],
      ),
    );
  }

  Future<void> _completeJob(JobCard jobCard, bool withMonitoring, String description) async {
    final now = DateTime.now();
    final user = currentEmployee?.name ?? 'User';
    final note = '\n\n[${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}] Completed by $user: $description';
    final updated = jobCard.copyWith(
      status: withMonitoring ? JobStatus.monitor : JobStatus.closed,
      completedBy: user,
      completedAt: now,
      monitoringStartedAt: withMonitoring ? now : null,
      notes: jobCard.notes + note,
    );
    final event = AssignmentEvent(
      assignedByName: withMonitoring ? 'Monitoring by $user' : 'Completed by $user',
      assignedByClockNo: currentEmployee?.clockNo ?? '',
      assigneeClockNos: [],
      assigneeNames: [],
      timestamp: now,
    );
    final newHistory = List<AssignmentEvent>.from(jobCard.assignmentHistory ?? []);
    newHistory.add(event);
    final finalUpdated = updated.copyWith(assignmentHistory: newHistory);
    try {
      await _firestoreService.saveJobCardOfflineAware(finalUpdated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(withMonitoring ? 'Job completed and monitoring started!' : 'Job completed!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error completing job: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _adjustmentMade(JobCard jobCard, String description) async {
    final now = DateTime.now();
    final user = currentEmployee?.name ?? 'User';
    final note = '\n\n[${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}] Adjustment made by $user: $description – restarted monitoring';
    final updated = jobCard.copyWith(
      monitoringStartedAt: now,
      notes: jobCard.notes + note,
    );
    final event = AssignmentEvent(
      assignedByName: 'Adjustment by $user',
      assignedByClockNo: currentEmployee?.clockNo ?? '',
      assigneeClockNos: [],
      assigneeNames: [],
      timestamp: now,
    );
    final newHistory = List<AssignmentEvent>.from(jobCard.assignmentHistory ?? []);
    newHistory.add(event);
    final finalUpdated = updated.copyWith(assignmentHistory: newHistory);
    try {
      await _firestoreService.saveJobCardOfflineAware(finalUpdated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Monitoring restarted!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error resetting monitoring: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showStatusChangeDialog(JobCard jobCard) {
    JobStatus selectedStatus = jobCard.status;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change Job Status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<JobStatus>(
                segments: const [
                  ButtonSegment(value: JobStatus.open, label: Text('Open')),
                  ButtonSegment(value: JobStatus.monitor, label: Text('Monitor')),
                  ButtonSegment(value: JobStatus.closed, label: Text('Closed')),

                ],
                selected: {selectedStatus},
                onSelectionChanged: (Set<JobStatus> selection) {
                  setDialogState(() => selectedStatus = selection.first);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                if (selectedStatus == jobCard.status) {
                  Navigator.pop(context);
                  return;
                }
                final now = DateTime.now();
                final user = currentEmployee?.name ?? 'User';
                final note = '\n\n[${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}] Status changed to ${selectedStatus.displayName} by $user';
                final updated = jobCard.copyWith(
                  status: selectedStatus,
                  monitoringStartedAt: selectedStatus == JobStatus.monitor ? now : null,
                  notes: jobCard.notes + note,
                );
                try {
                  await _firestoreService.saveJobCardOfflineAware(updated);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Status changed to ${selectedStatus.displayName}!')));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error changing status: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Change Status'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentButtons(JobCard jobCard) {
    // Hide all assignment buttons if job is closed
    if (jobCard.status == JobStatus.closed) return const SizedBox.shrink();

    final isAssigned = jobCard.assignedClockNos?.contains(currentEmployee?.clockNo ?? '') ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: isAssigned ? () => _selfUnassign(jobCard) : () => _selfAssign(jobCard),
              icon: Icon(isAssigned ? Icons.remove_circle : Icons.person_add, size: 24),
              label: Text(
                isAssigned ? 'Unassign' : 'Assign',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isAssigned ? Colors.orange : const Color(0xFF10B981),
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (isManager)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _showAssignCompleteDialog(context, jobCard),
                icon: const Icon(Icons.group_add, size: 24),
                label: const Text(
                  'Manage',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF8C42),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeroHeader(JobCard jobCard) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Job #${jobCard.jobCardNumber ?? jobCard.id ?? 'N/A'}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.white)),
                GestureDetector(
                  onTap: isManager ? () => _showStatusChangeDialog(jobCard) : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: jobCard.status == JobStatus.closed ? Colors.green : jobCard.status == JobStatus.monitor ? Colors.orange : Colors.blue,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          jobCard.status.displayName.toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        if (isManager) const SizedBox(width: 4),
                        if (isManager) const Icon(Icons.edit, color: Colors.white, size: 14),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Count - $_reoccurrenceCount',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'P${jobCard.priority}',
                    style: TextStyle(
                      color: _getPriorityColor('P${jobCard.priority}'),
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextSpan(
                    text: ' | ${jobCard.department ?? 'N/A'} > ${jobCard.area ?? 'N/A'} > ${jobCard.machine ?? 'N/A'} > ${jobCard.part ?? 'N/A'}',
                    style: const TextStyle(fontSize: 15.5, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCombinedCard(JobCard jobCard) {
    final parsedComments = _parseComments(jobCard.comments);
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Description', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 6),
            Text(jobCard.description, style: const TextStyle(fontSize: 15.5, color: Colors.white)),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Comments', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                if (_canAddComments)
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: _showAddCommentDialog,
                        icon: const Icon(Icons.add_comment, size: 20),
                        label: const Text('Add Comment'),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF8C42)),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => _addPhoto(jobCard, 'comments'),
                        icon: const Icon(Icons.camera_alt, size: 20),
                        label: const Text('Add Photo'),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF8C42)),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (parsedComments.isEmpty)
              const Text('No comments yet', style: TextStyle(color: Colors.white70)),
            if (parsedComments.isNotEmpty)
              ...parsedComments.map((comment) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(comment, style: const TextStyle(fontSize: 15, color: Colors.white)),
                  )),

            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Notes', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                Row(
                  children: [
                    if (_canAddNotes)
                      TextButton.icon(
                        onPressed: _showAddNoteDialog,
                        icon: const Icon(Icons.note_add, size: 20),
                        label: const Text('Add Note'),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF8C42)),
                      ),
                    if (_canAddNotes) const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _addPhoto(jobCard, 'notes'),
                      icon: const Icon(Icons.camera_alt, size: 20),
                      label: const Text('Add Photo'),
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF8C42)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (jobCard.notes.isNotEmpty) ..._parseNotes(jobCard.notes).map((note) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(note, style: const TextStyle(fontSize: 15, color: Colors.white)),
                )),
            if (jobCard.notes.isEmpty)
              const Text('No notes', style: TextStyle(color: Colors.white70)),


          ],
        ),
      ),
    );
  }

  Widget _buildDetailsCard(JobCard jobCard) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Details', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            _buildDetailRow('Created By', jobCard.operator ?? 'Unknown'),
            if (jobCard.completedBy != null) _buildDetailRow('Completed By', jobCard.completedBy!),
            if (jobCard.assignedNames != null && jobCard.assignedNames!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: 120, child: Text('Assigned To:', style: TextStyle(fontWeight: FontWeight.w500, color: Colors.white70))),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: jobCard.assignedNames!.map((name) {
                        return Chip(
                          avatar: const Icon(Icons.person, size: 16, color: Colors.green),
                          label: Text(name, style: const TextStyle(color: Colors.white, fontSize: 13)),
                          backgroundColor: Colors.white12,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityLogCard(JobCard jobCard) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        title: const Text('Activity Log', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (jobCard.createdAt != null) _buildTimelineRow('Created', jobCard.createdAt!),
                if (jobCard.startedAt != null) _buildTimelineRow('Started', jobCard.startedAt!),
                if (jobCard.notificationReceivedAt != null) _buildTimelineRow('Notification Received', jobCard.notificationReceivedAt!),
                if (jobCard.completedAt != null) _buildTimelineRow('Completed', jobCard.completedAt!),
                if (jobCard.monitoringStartedAt != null) _buildTimelineRow('Monitoring Started', jobCard.monitoringStartedAt!),
                if (jobCard.lastUpdatedAt != null) _buildTimelineRow('Last Updated', jobCard.lastUpdatedAt!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignmentLogCard(JobCard jobCard) {
    final parsedHistory = _parseAssignmentHistory(jobCard.assignmentHistory ?? []);
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        title: const Text('Assignment Log', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: parsedHistory.isEmpty
                  ? [const Text('No assignment history', style: TextStyle(color: Colors.white70))]
                  : parsedHistory.map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(entry, style: const TextStyle(fontSize: 15, color: Colors.white), textAlign: TextAlign.left),
                        ),
                      )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 200, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white70))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 15.5, color: Colors.white))),
        ],
      ),
    );
  }

  Widget _buildTimelineRow(String label, DateTime dateTime) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white70))),
          SizedBox(width: 220, child: Text(_formatDateTime(dateTime), textAlign: TextAlign.right, style: const TextStyle(fontSize: 15.5, color: Colors.white))),
        ],
      ),
    );
  }

  List<String> _parseComments(String comments) => comments.split('\n\n').where((c) => c.trim().isNotEmpty).toList();

  List<String> _parseNotes(String notes) => notes.split('\n\n').where((c) => c.trim().isNotEmpty).toList();

  List<String> _parseAssignmentHistory(List<AssignmentEvent> history) {
    return history.reversed.map((event) {
      final formatted = event.assigneeNames.isEmpty
          ? event.assignedByName
          : '${event.isUnassign ? 'Unassigned' : 'Assigned to'} ${event.assigneeNames.join(', ')} by ${event.assignedByName}';
      return '[${_formatDateTime(event.timestamp)}] $formatted';
    }).toList();
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
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} - ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}