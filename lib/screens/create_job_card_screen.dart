import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
import '../main.dart' show currentEmployee;
import 'job_card_detail_screen.dart';
import 'view_job_cards_screen.dart';
import '../theme/app_theme.dart';

class CreateJobCardScreen extends StatefulWidget {
  const CreateJobCardScreen({super.key});

  @override
  State<CreateJobCardScreen> createState() => _CreateJobCardScreenState();
}

class _CreateJobCardScreenState extends State<CreateJobCardScreen> {
  final _formKey = GlobalKey<FormState>();
  String? selectedDepartment;
  String? selectedArea;
  String? selectedMachine;
  String part = '';
  late final TextEditingController _partController = TextEditingController();
  JobType? jobType;
  int priority = 3;
  String description = '';
  bool _isLoading = false;
  List<Map<String, dynamic>> photos = [];

  final List<Color> priorityColors = [
    Colors.transparent,
    Colors.green[500]!,
    Colors.lightGreen[500]!,
    Colors.amber[500]!,
    Colors.deepOrange[500]!,
    Colors.red[700]!,
  ];

  final List<String> priorityDescriptions = [
    '',
    'No effect on production — routine or planned work',
    'Minor impact — production continuing',
    'Moderate impact — degraded operation',
    'Significant impact — output reduced',
    'Production is standing — stopped',
  ];

  final FirestoreService _firestoreService = FirestoreService();

  bool get _isWide => MediaQuery.of(context).size.width >= 1000;

  @override
  void initState() {
    super.initState();

    // Default to logged-in user's department + auto-load areas
    if (currentEmployee?.department != null && currentEmployee!.department.isNotEmpty) {
      selectedDepartment = currentEmployee!.department;
    }
  }
  Color _getPriorityColor(String priority) {
    final num = int.tryParse(priority.substring(1)) ?? 0;
    final appColors = Theme.of(context).appColors;
    switch (num) {
      case 1: return appColors.priority1;
      case 2: return appColors.priority2;
      case 3: return appColors.priority3;
      case 4: return appColors.priority4;
      case 5: return appColors.priority5;
      default: return Colors.grey;
    }
  }

  Color _getStatusColor(String status) {
    final appColors = Theme.of(context).appColors;
    switch (status.toLowerCase()) {
      case 'open': return appColors.statusOpen;
      case 'in_progress':
      case 'in progress': return appColors.statusInProgress;
      case 'completed':
      case 'monitor': return appColors.statusCompleted;
      case 'closed':
      case 'cancelled': return appColors.statusCancelled;
      default: return Colors.grey;
    }
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.hour}:${dt.minute.toString().padLeft(2,'0')} ${dt.day}/${dt.month}';
  }

  String get operatorName => currentEmployee?.name ?? 'Unknown';

  Future<List<String>> _loadPreviousParts() async {
    if (selectedDepartment == null || selectedArea == null || selectedMachine == null) return [];
    return await _firestoreService.getPreviousParts(selectedDepartment!, selectedArea!, selectedMachine!);
  }

  void _clearSelections() {
    setState(() {
      selectedDepartment = selectedArea = selectedMachine = null;
      part = '';
      _partController.clear();
    });
  }

  Future<void> _saveJobCard() async {
    if (!_formKey.currentState!.validate()) return;
    if (selectedDepartment == null || selectedArea == null || selectedMachine == null || part.isEmpty || jobType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Step 1: Upload all photos to Firebase Storage FIRST
      final uploadedPhotos = await _uploadPhotos();

      // Step 2: Create JobCard with the uploaded photo maps (now containing URLs)
      final jobCard = JobCard(
        department: selectedDepartment!,
        area: selectedArea!,
        machine: selectedMachine!,
        part: part,
        type: jobType!,
        priority: priority,
        operator: operatorName,
        operatorClockNo: currentEmployee?.clockNo,
        description: description,
        photos: uploadedPhotos,   // ← THIS WAS THE MISSING PART
      );

      // Step 3: Save
      await _firestoreService.saveJobCardOfflineAware(jobCard);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job Card saved with photos!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving job card: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addPhoto(String section) async {
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

    // MAXIMUM practical compression for job cards (70-85% smaller files)
    final compressedFile = await FlutterImageCompress.compressAndGetFile(
      pickedFile.path,
      '${pickedFile.path}_compressed.jpg',
      minWidth: 1024,
      minHeight: 1024,
      quality: 70,
      rotate: 0,
      keepExif: false,
      format: CompressFormat.jpeg,
    );
    if (compressedFile == null) return;

    setState(() {
      photos.add({'file': compressedFile.path, 'section': section});
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo added & heavily compressed!')));
    }
  }

  Future<List<Map<String, dynamic>>> _uploadPhotos() async {
    if (photos.isEmpty) return [];
    final List<Map<String, dynamic>> uploaded = [];
    final storage = FirebaseStorage.instance;
    const uuid = Uuid();

    for (int i = 0; i < photos.length; i++) {
      final photoData = photos[i];
      final filePath = photoData['file'] as String?;
      if (filePath == null) continue;

      try {
        final file = File(filePath);
        if (!file.existsSync()) continue;

        final jobUuid = uuid.v4();
        final storageRef = storage
            .ref()
            .child('job_cards/$jobUuid/photos/photo_${i}_${DateTime.now().millisecondsSinceEpoch}.jpg');

        await storageRef.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
        final downloadUrl = await storageRef.getDownloadURL();

        uploaded.add({
          'url': downloadUrl,
          'section': photoData['section'] as String? ?? 'General',
          'addedBy': FirebaseAuth.instance.currentUser?.uid ?? 'legacy',
          'timestamp': DateTime.now().toIso8601String(),
          'department': selectedDepartment,
          'machine': selectedMachine,
          'location': selectedArea,
          'part': part,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Photo ${i + 1} uploaded')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed photo ${i + 1}: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
    return uploaded;
  }

  Widget _buildPhotosPreview() {
    if (photos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text('No photos added yet', style: TextStyle(color: Colors.grey)),
      );
    }

    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        itemBuilder: (context, index) {
          final filePath = photos[index]['file'] as String?;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(filePath!),
                    height: 120,
                    width: 120,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        photos.removeAt(index);
                      });
                    },
                    child: const CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.red,
                      child: Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSimilarJobCards() {
    return StreamBuilder<List<JobCard>>(
      stream: _firestoreService.getAllJobCards(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text('Error loading similar jobs: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
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

        final allJobs = snapshot.data!;
        final similarJobs = allJobs.where((j) {
          if (selectedDepartment != null && j.department != selectedDepartment) return false;
          if (selectedArea != null && j.area != selectedArea) return false;
          if (selectedMachine != null && j.machine != selectedMachine) return false;
          if (part.isNotEmpty && j.part != part) return false;
          return true;
        }).toList()
          ..sort((a, b) {
            final statusA = a.status == JobStatus.open ? 0 : 1;
            final statusB = b.status == JobStatus.open ? 0 : 1;
            if (statusA != statusB) return statusA.compareTo(statusB);
            return (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
          });

        final topJobs = similarJobs.take(20).toList();

        String path = '';
        if (selectedDepartment != null) path = selectedDepartment!;
        if (selectedArea != null) path += ' > $selectedArea';
        if (selectedMachine != null) path += ' > $selectedMachine';
        if (part.isNotEmpty) path += ' > $part';

        if (topJobs.isEmpty) {
          return Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  path.isEmpty ? 'Select department to see previous jobs' : 'No matching jobs for current selection',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          );
        }

        return Column(
          children: [
            Text(
              path.isEmpty ? 'Select department to see previous jobs' : 'Previous jobs for $path',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 400,
              child: ListView.builder(
                itemCount: topJobs.length,
                itemBuilder: (context, index) {
                  final job = topJobs[index];
                  return Card(
                    elevation: 4,
                    margin: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => JobCardDetailScreen(jobCard: job)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // First Row - Fixed overflow
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${job.department} > ${job.machine} > ${job.area}',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Created by: ${job.operator}',
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),

                            // Second Row - Fixed overflow
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _getPriorityColor('P${job.priority}'),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'P${job.priority}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    job.description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w500, fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),

                            // Third Row - Fixed overflow
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(job.status.name).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    job.status.displayName,
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blueGrey.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    job.type.displayName,
                                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    job.assignedNames?.join(', ') ?? 'Unassigned',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatDateTime(job.lastUpdatedAt),
                                  style: const TextStyle(color: Color(0xFFFF8C42), fontSize: 11),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ViewJobCardsScreen(
                  filterDepartment: selectedDepartment,
                  filterArea: selectedArea,
                  filterMachine: selectedMachine,
                  filterPart: part,
                ))),
                icon: const Icon(Icons.visibility, size: 16),
                label: const Text('View All Similar Job Cards'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFF8C42),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNarrowLayout() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _firestoreService.getFactoryStructure(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Error loading structure: ${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data!;
            final areas = selectedDepartment != null ? (data[selectedDepartment] as Map<String, dynamic>? ?? {}).keys.toList() : <String>[];
            final machines = selectedArea != null && selectedDepartment != null
                ? (data[selectedDepartment]?[selectedArea] as List<dynamic>? ?? []).cast<String>()
                : <String>[];

            return ListView(
              children: [
                if (selectedDepartment != null || selectedArea != null || selectedMachine != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).appColors.cardSurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Selection - ${selectedDepartment ?? ''}${selectedArea != null ? ' > $selectedArea' : ''}${selectedMachine != null ? ' > $selectedMachine' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: _clearSelections,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                 if (selectedDepartment == null) ...[
                   const Text('Department', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                   const SizedBox(height: 8),
                   Wrap(
                     spacing: 8,
                     runSpacing: 4,
                       children: data.keys.map((dept) => ChoiceChip(
                         label: Text(dept),
                         selected: selectedDepartment == dept,
                         onSelected: (_) => setState(() {
                           selectedDepartment = dept;
                           selectedArea = null;
                           selectedMachine = null;
                           part = '';
                         }),
                         padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                         labelStyle: selectedDepartment == dept ? const TextStyle(color: Color(0xFFFF8C42)) : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
                       )).toList(),
                   ),
                 ],
                if (selectedDepartment != null && selectedArea == null) ...[
                   const SizedBox(height: 8),
                   const Text('Area / Section', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                   const SizedBox(height: 8),
                   Wrap(
                     spacing: 8,
                     runSpacing: 4,
                     children: areas.map((area) => ChoiceChip(
                       label: Text(area),
                       selected: selectedArea == area,
                       onSelected: (_) => setState(() {
                         selectedArea = area;
                         selectedMachine = null;
                         part = '';
                       }),
                       padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                       labelStyle: selectedArea == area ? const TextStyle(color: Color(0xFFFF8C42)) : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
                     )).toList(),
                   ),
                 ],
                if (selectedArea != null && selectedMachine == null) ...[
                   const SizedBox(height: 8),
                   const Text('Machine / Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                   const SizedBox(height: 8),
                   Wrap(
                     spacing: 8,
                     runSpacing: 4,
                     children: machines.map((machine) => ChoiceChip(
                       label: Text(machine),
                       selected: selectedMachine == machine,
                       onSelected: (_) => setState(() {
                         selectedMachine = machine;
                         part = '';
                       }),
                       padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                       labelStyle: selectedMachine == machine ? const TextStyle(color: Color(0xFFFF8C42)) : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
                     )).toList(),
                   ),
                 ],
                if (selectedMachine != null) ...[
                  const SizedBox(height: 8),
                  const Text('Part / Component', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  FutureBuilder<List<String>>(
                    future: _loadPreviousParts(),
                    builder: (context, snapshot) {
                      final previousParts = snapshot.data ?? [];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (previousParts.isNotEmpty)
                            Wrap(
                              spacing: 8,
                              children: previousParts.map((p) => ActionChip(
                                label: Text(p),
                                onPressed: () => setState(() { part = p; _partController.text = p; }),
                              )).toList(),
                            ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _partController,
                            decoration: const InputDecoration(
                              labelText: 'Type part or tap suggestion above',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) => part = v,
                            validator: (v) => v!.isEmpty ? 'Required' : null,
                          ),
                        ],
                      );
                    },
                  ),
                ],
                const SizedBox(height: 12),
                const Text('Job Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: JobType.values.map((type) => ChoiceChip(
                    label: Text(type.displayName),
                    selected: jobType == type,
                    onSelected: (_) => setState(() => jobType = jobType == type ? null : type),
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                    labelStyle: jobType == type ? const TextStyle(color: Color(0xFFFF8C42)) : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
                  )).toList(),
                ),
                const SizedBox(height: 8),
                const Text('Priority (1 = Low → 5 = Urgent)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(5, (i) {
                    final num = i + 1;
                    return ChoiceChip(
                      label: Text('$num'),
                      selected: priority == num,
                      onSelected: (_) => setState(() => priority = num),
                      backgroundColor: priorityColors[num],
                      selectedColor: priorityColors[num].withValues(alpha: 0.2),
                      labelStyle: TextStyle(color: num == priority ? const Color(0xFFFF8C42) : Colors.white, fontWeight: num == priority ? FontWeight.bold : FontWeight.normal),
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                    );
                  }),
                ),
                const SizedBox(height: 10),
                // Priority reference table — highlights the selected level
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Table(
                    border: TableBorder.all(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(8)),
                    columnWidths: const {
                      0: FixedColumnWidth(44),
                      1: FlexColumnWidth(),
                    },
                    children: [
                      // Header
                      const TableRow(
                        decoration: BoxDecoration(color: Color(0xFF1a3a5c)),
                        children: [
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            child: Text('P', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            child: Text('Production Impact', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                      // P1 – P5 rows
                      ...List.generate(5, (i) {
                        final num = i + 1;
                        final isSelected = priority == num;
                        return TableRow(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? priorityColors[num].withValues(alpha: 0.15)
                                : (i.isEven ? Theme.of(context).colorScheme.surfaceContainerHighest : Theme.of(context).colorScheme.surface),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                              child: Center(
                                child: Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: priorityColors[num],
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$num',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              child: Text(
                                priorityDescriptions[num],
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                                  color: isSelected ? Colors.black87 : Colors.black54,
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 20),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withValues(alpha: 70)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Describe the fault clearly:', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w700, fontSize: 13)),
                      SizedBox(height: 5),
                      Text('• What happened and what you observed', style: TextStyle(fontSize: 12.5)),
                      Text('• Any error codes or alarms displayed', style: TextStyle(fontSize: 12.5)),
                      Text('• When it started and how often it occurs', style: TextStyle(fontSize: 12.5)),
                    ],
                  ),
                ),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Job Description',
                    hintText: 'e.g. Motor tripping on overload — error E07 on HMI. Fault started at 07:00, occurs every 20 min under full load.',
                    hintStyle: TextStyle(fontSize: 12.5),
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                  onChanged: (v) => description = v,
                ),
                 const SizedBox(height: 24),
                 const Text('Photos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                 const SizedBox(height: 8),
                 ElevatedButton.icon(
                   onPressed: part.isNotEmpty && description.isNotEmpty ? () => _addPhoto('Description') : null,
                   icon: const Icon(Icons.add_a_photo),
                   label: const Text('Add Photo (Camera/Gallery)'),
                 ),
                 const SizedBox(height: 12),
                _buildPhotosPreview(),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveJobCard,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8C42),
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      textStyle: const TextStyle(fontSize: 24),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.black)
                        : const Text('Save Job Card', style: TextStyle(color: Colors.black)),
                  ),
                ),
                const SizedBox(height: 12),
                _buildSimilarJobCards(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildWideLayout() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _firestoreService.getFactoryStructure(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error loading structure: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!;
        final areas = selectedDepartment != null ? (data[selectedDepartment] as Map<String, dynamic>? ?? {}).keys.toList() : <String>[];
        final machines = selectedArea != null && selectedDepartment != null
            ? (data[selectedDepartment]?[selectedArea] as List<dynamic>? ?? []).cast<String>()
            : <String>[];

        return Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      if (selectedDepartment != null || selectedArea != null || selectedMachine != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).appColors.cardSurface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Selection - ${selectedDepartment ?? ''}${selectedArea != null ? ' > $selectedArea' : ''}${selectedMachine != null ? ' > $selectedMachine' : ''}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: _clearSelections,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                       if (selectedDepartment == null) ...[
                         const Text('Department', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                         const SizedBox(height: 8),
                         Wrap(
                           spacing: 8,
                           runSpacing: 4,
                           children: data.keys.map((dept) => ChoiceChip(
                             label: Text(dept),
                             selected: selectedDepartment == dept,
                             onSelected: (_) => setState(() {
                               selectedDepartment = dept;
                               selectedArea = null;
                               selectedMachine = null;
                               part = '';
                             }),
                             padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                           )).toList(),
                         ),
                       ],
                      if (selectedDepartment != null && selectedArea == null) ...[
                         const SizedBox(height: 8),
                         const Text('Area / Section', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                         const SizedBox(height: 8),
                         Wrap(
                           spacing: 8,
                           runSpacing: 4,
                           children: areas.map((area) => ChoiceChip(
                             label: Text(area),
                             selected: selectedArea == area,
                             onSelected: (_) => setState(() {
                               selectedArea = area;
                               selectedMachine = null;
                               part = '';
                             }),
                             padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                           )).toList(),
                         ),
                       ],
                      if (selectedArea != null && selectedMachine == null) ...[
                         const SizedBox(height: 8),
                         const Text('Machine / Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                         const SizedBox(height: 8),
                         Wrap(
                           spacing: 8,
                           runSpacing: 4,
                           children: machines.map((machine) => ChoiceChip(
                             label: Text(machine),
                             selected: selectedMachine == machine,
                             onSelected: (_) => setState(() {
                               selectedMachine = machine;
                               part = '';
                             }),
                             padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                           )).toList(),
                         ),
                       ],
                      if (selectedMachine != null) ...[
                        const SizedBox(height: 12),
                        const Text('Part / Component', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        FutureBuilder<List<String>>(
                          future: _loadPreviousParts(),
                          builder: (context, snapshot) {
                            final previousParts = snapshot.data ?? [];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (previousParts.isNotEmpty)
                                  Wrap(
                                    spacing: 8,
                                    children: previousParts.map((p) => ActionChip(
                                      label: Text(p),
                                      onPressed: () => setState(() { part = p; _partController.text = p; }),
                                    )).toList(),
                                  ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _partController,
                                  decoration: const InputDecoration(
                                    labelText: 'Type part or tap suggestion above',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (v) => part = v,
                                  validator: (v) => v!.isEmpty ? 'Required' : null,
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      const Text('Job Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: JobType.values.map((type) => ChoiceChip(
                          label: Text(type.displayName),
                          selected: jobType == type,
                          onSelected: (_) => setState(() => jobType = jobType == type ? null : type),
                          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                        )).toList(),
                      ),
                      const SizedBox(height: 8),
                      const Text('Priority (1 = Low → 5 = Urgent)', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(5, (i) {
                          final num = i + 1;
                          return ChoiceChip(
                            label: Text('$num'),
                            selected: priority == num,
                            onSelected: (_) => setState(() => priority = num),
                            backgroundColor: priorityColors[num],
                           selectedColor: priorityColors[num].withValues(alpha: 0.2),
                            labelStyle: TextStyle(color: num == priority ? const Color(0xFFFF8C42) : Colors.white, fontWeight: num == priority ? FontWeight.bold : FontWeight.normal),
                            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                          );
                        }),
                      ),
                      const SizedBox(height: 8),
                      if (priority > 0)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                           color: priorityColors[priority].withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            priorityDescriptions[priority],
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 20),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.withValues(alpha: 70)),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Describe the fault clearly:', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w700, fontSize: 13)),
                            SizedBox(height: 5),
                            Text('• What happened and what you observed', style: TextStyle(fontSize: 12.5)),
                            Text('• Any error codes or alarms displayed', style: TextStyle(fontSize: 12.5)),
                            Text('• When it started and how often it occurs', style: TextStyle(fontSize: 12.5)),
                          ],
                        ),
                      ),
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Job Description',
                          hintText: 'e.g. Motor tripping on overload — error E07 on HMI. Fault started at 07:00, occurs every 20 min under full load.',
                          hintStyle: TextStyle(fontSize: 12.5),
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 4,
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                        onChanged: (v) => description = v,
                      ),
                      const SizedBox(height: 24),
                      const Text('Photos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: part.isNotEmpty && description.isNotEmpty ? () => _addPhoto('Description') : null,
                        icon: const Icon(Icons.add_a_photo),
                        label: const Text('Add Photo (Camera/Gallery)'),
                      ),
                      const SizedBox(height: 12),
                      _buildPhotosPreview(),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _saveJobCard,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF8C42),
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            textStyle: const TextStyle(fontSize: 24),
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(color: Colors.black)
                              : const Text('Save Job Card', style: TextStyle(color: Colors.black)),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _buildSimilarJobCards(),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('Building CreateJobCardScreen - jobType: $jobType');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Job Card'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(operatorName),
          ),
        ],
      ),
      body: _isWide ? _buildWideLayout() : _buildNarrowLayout(),
    );
  }
}