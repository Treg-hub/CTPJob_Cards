import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/job_card.dart';
import '../services/connectivity_service.dart';
import '../services/firestore_service.dart';
import '../main.dart' show currentEmployee, realEmployee;
import '../utils/persona_audit.dart';
import '../utils/presence_gating.dart';
import 'job_card_detail_screen.dart';
import 'view_job_cards_screen.dart';
import '../theme/app_theme.dart';
import '../utils/screen_insets.dart';
import '../widgets/job_card_badges.dart';

class CreateJobCardScreen extends StatefulWidget {
  const CreateJobCardScreen({super.key});

  @override
  State<CreateJobCardScreen> createState() => _CreateJobCardScreenState();
}

class _CreateJobCardScreenState extends State<CreateJobCardScreen>
    with WidgetsBindingObserver {
  static const String _draftPrefsKey = 'jobCardCreateDraft';

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

  // Creation is online-only BY DESIGN: an offline-created job would alert
  // nobody and the operator would wait for a technician who was never
  // notified. We block early with an explanation instead of failing the save.
  bool _isOnline = true;
  bool _saved = false;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

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

  /// Hides the Pre Press Spec type unless the selected department is Pre Press.
  List<JobType> get _availableJobTypes {
    if (selectedDepartment != 'Pre Press') {
      return JobType.values.where((t) => t != JobType.specialist).toList();
    }
    return JobType.values;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Default to the logged-in user's department, but NOT for Mechanical/Electrical
    // workers who roam the whole factory and should pick their department per job.
    final dept = currentEmployee?.department ?? '';
    final deptLower = dept.toLowerCase();
    final isMechOrElec =
        deptLower.contains('mechanical') || deptLower.contains('electrical');
    if (dept.isNotEmpty && !isMechOrElec) {
      selectedDepartment = dept;
    }

    _initConnectivity();
    _restoreDraft();
    WidgetsBinding.instance.addPostFrameCallback((_) => _guardOffSiteCreate());
  }

  void _guardOffSiteCreate() {
    if (!mounted) return;
    final isOnSite = realEmployee?.isOnSite ?? true;
    if (PresenceGating.canCreateJobCard(
      emp: currentEmployee,
      isOnSite: isOnSite,
    )) {
      return;
    }
    PresenceGating.showOffSiteSnackBar(
      context,
      PresenceGating.offSiteCreateJobMessage,
    );
    Navigator.pop(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connSub?.cancel();
    _persistDraft();
    _partController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounding may precede process death — persist so the worker who
    // walks to find signal doesn't retype the whole form.
    if (state == AppLifecycleState.paused) _persistDraft();
  }

  Future<void> _initConnectivity() async {
    if (kIsWeb) return;
    final online = await ConnectivityService().isOnline();
    if (mounted) setState(() => _isOnline = online);
    _connSub = ConnectivityService().connectivityStream.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (mounted && online != _isOnline) setState(() => _isOnline = online);
    });
  }

  // ==================== LOCAL DRAFT ====================
  bool get _hasDraftContent =>
      selectedDepartment != null ||
      part.isNotEmpty ||
      description.isNotEmpty ||
      photos.isNotEmpty;

  Future<void> _persistDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_saved || !_hasDraftContent) {
        await prefs.remove(_draftPrefsKey);
        return;
      }
      await prefs.setString(
        _draftPrefsKey,
        jsonEncode({
          'department': selectedDepartment,
          'area': selectedArea,
          'machine': selectedMachine,
          'part': part,
          'type': jobType?.name,
          'priority': priority,
          'description': description,
          'photos': photos
              .map((p) => {'file': p['file'], 'section': p['section']})
              .toList(),
        }),
      );
    } catch (e) {
      debugPrint('Draft persist failed: $e');
    }
  }

  Future<void> _restoreDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;

      // Photos survive only while their compressed temp files still exist.
      final restoredPhotos = <Map<String, dynamic>>[];
      for (final p in (data['photos'] as List? ?? const [])) {
        if (p is Map && p['file'] is String && File(p['file'] as String).existsSync()) {
          restoredPhotos.add({'file': p['file'], 'section': p['section'] ?? 'Description'});
        }
      }

      if (!mounted) return;
      setState(() {
        selectedDepartment = data['department'] as String? ?? selectedDepartment;
        selectedArea = data['area'] as String?;
        selectedMachine = data['machine'] as String?;
        part = data['part'] as String? ?? '';
        _partController.text = part;
        final typeName = data['type'] as String?;
        jobType = typeName != null ? JobType.fromString(typeName) : null;
        priority = data['priority'] as int? ?? 3;
        description = data['description'] as String? ?? '';
        photos = restoredPhotos;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft restored — your unsent job card was kept')),
      );
    } catch (e) {
      debugPrint('Draft restore failed: $e');
    }
  }

  Widget _buildOfflineBanner() {
    if (_isOnline) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red),
      ),
      child: const Row(
        children: [
          Icon(Icons.wifi_off, color: Colors.red, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No connection — technicians cannot be alerted. Move to an area '
              'with signal to submit. Your entries are kept as a draft.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
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

  // Stable idempotency key for the in-flight submit. Generated once per create
  // intent and reused across retries (so a lost response can't duplicate the
  // job); cleared on success so the next create gets a fresh id.
  String? _pendingClientRef;

  Future<void> _saveJobCard() async {
    if (!guardPersonaSubmit(context)) return;
    final isOnSite = realEmployee?.isOnSite ?? true;
    if (!PresenceGating.canCreateJobCard(
      emp: currentEmployee,
      isOnSite: isOnSite,
    )) {
      PresenceGating.showOffSiteSnackBar(
        context,
        PresenceGating.offSiteCreateJobMessage,
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (selectedDepartment == null || selectedArea == null || selectedMachine == null || part.isEmpty || jobType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields'), backgroundColor: Colors.red),
      );
      return;
    }

    // Re-check connectivity at the moment of save — the photo uploads and the
    // numbering transaction both need the server, and an offline job card
    // would alert nobody.
    if (!kIsWeb && !await ConnectivityService().isOnline()) {
      if (mounted) {
        setState(() => _isOnline = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No connection — technicians cannot be alerted. Your draft is saved; submit when you have signal.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      await _persistDraft();
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Step 1: Upload all photos to Firebase Storage FIRST
      final uploadedPhotos = await _uploadPhotos();

      // Step 2: Create JobCard with the uploaded photo maps (now containing URLs)
      final session = writeAttributionEmployee ?? currentEmployee;
      final jobCard = JobCard(
        department: selectedDepartment!,
        area: selectedArea!,
        machine: selectedMachine!,
        part: part,
        type: jobType!,
        priority: priority,
        operator: session?.name ?? operatorName,
        operatorClockNo: session?.clockNo,
        description: description,
        photos: uploadedPhotos,   // ← THIS WAS THE MISSING PART
      );

      // Step 3: Save (idempotent — a stable client_ref dedupes a retried submit).
      _pendingClientRef ??= const Uuid().v4();
      await _firestoreService.saveJobCardOfflineAware(jobCard, clientRef: _pendingClientRef);
      _pendingClientRef = null; // success — next create gets a fresh id

      // Submitted — drop the local draft.
      _saved = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_draftPrefsKey);
      } catch (_) {}

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
    if (!guardPersonaSubmit(context)) return;
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
    final folderUuid = uuid.v4();

    for (int i = 0; i < photos.length; i++) {
      final photoData = photos[i];
      final filePath = photoData['file'] as String?;
      if (filePath == null) continue;

      try {
        final file = File(filePath);
        if (!file.existsSync()) {
          // Fail loudly rather than silently skipping — a missing temp file
          // (OS cache eviction, etc.) used to drop photos with no signal.
          if (!kIsWeb) {
            FirebaseCrashlytics.instance.recordError(
            Exception('Compressed photo missing before upload'),
            StackTrace.current,
            reason: 'photo_temp_file_missing',
            information: ['path:$filePath'],
          );
          }
          throw Exception(
            'Photo ${i + 1} file was cleaned up before upload — please re-add it and retry',
          );
        }

        final storageRef = storage
            .ref()
            .child('job_cards/$folderUuid/photos/photo_${i}_${DateTime.now().millisecondsSinceEpoch}.jpg');

        await storageRef.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
        final downloadUrl = await storageRef.getDownloadURL();

        uploaded.add({
          'url': downloadUrl,
          'section': photoData['section'] as String? ?? 'General',
          'addedBy': FirebaseAuth.instance.currentUser?.uid ?? 'legacy',
          'addedByName': currentEmployee?.name ?? 'Unknown',
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
      } catch (e, st) {
        if (!kIsWeb) {
          FirebaseCrashlytics.instance.recordError(
          e,
          st,
          reason: 'photo_upload_failed_at_create',
          information: ['index:$i', 'path:$filePath'],
        );
        }
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

  Stream<List<JobCard>>? _similarJobsStream() {
    if (selectedDepartment == null) return null;

    // Use the most specific indexed query available to minimise reads.
    // Narrows server-side by dept+area+machine+part (when set), then type.
    // Falls back to broader queries as selection gets less specific.
    if (selectedMachine != null && part.isNotEmpty && jobType != null) {
      return _firestoreService.getExactRelatedJobCardsStream(
        department: selectedDepartment!,
        area: selectedArea!,
        machine: selectedMachine!,
        part: part,
        type: jobType!.name,
      );
    }
    if (selectedMachine != null && part.isNotEmpty) {
      return _firestoreService.getExactAllTypesStream(
        department: selectedDepartment!,
        area: selectedArea!,
        machine: selectedMachine!,
        part: part,
      );
    }
    if (selectedMachine != null) {
      return _firestoreService.getAllPartsStream(
        department: selectedDepartment!,
        area: selectedArea!,
        machine: selectedMachine!,
      );
    }
    if (selectedArea != null) {
      return _firestoreService.getRelatedExcludingPartStream(
        department: selectedDepartment!,
        area: selectedArea!,
        machine: '',
        type: jobType?.name ?? 'mechanical',
      );
    }
    return null;
  }

  Widget _buildSimilarJobCards() {
    final stream = _similarJobsStream();

    if (stream == null) {
      return Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              'Select department to see previous jobs',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    return StreamBuilder<List<JobCard>>(
      stream: stream,
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

        final topJobs = snapshot.data!;

        String path = selectedDepartment ?? '';
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
                  'No matching jobs for current selection',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          );
        }

        return Column(
          children: [
            Text(
              'Previous jobs for $path',
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
                                PriorityBadge(
                                  priority: job.priority,
                                  style: PriorityBadgeStyle.filled,
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
                                JobStatusChip(
                                  status: job.status,
                                  style: PriorityBadgeStyle.filled,
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blueGrey,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    job.type.displayName,
                                    style: const TextStyle(color: Colors.white, fontSize: 11),
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
      padding: ScreenInsets.symmetricScroll(context),
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
                _buildOfflineBanner(),
                if (selectedDepartment != null || selectedArea != null || selectedMachine != null) ...[
                  Container(
                    padding: const EdgeInsets.only(left: 16, right: 4, top: 4, bottom: 4),
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
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _clearSelections,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          visualDensity: VisualDensity.compact,
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
                           if (jobType == JobType.specialist && dept != 'Pre Press') {
                             jobType = null;
                           }
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
                  children: _availableJobTypes.map((type) => ChoiceChip(
                    label: Text(type.displayName),
                    selected: jobType == type,
                    onSelected: (_) => setState(() => jobType = jobType == type ? null : type),
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                    labelStyle: jobType == type ? const TextStyle(color: Color(0xFFFF8C42)) : TextStyle(color: Theme.of(context).appColors.chipUnselectedLabel),
                  )).toList(),
                ),
                if (jobType == JobType.maintenance) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 30),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withValues(alpha: 120)),
                    ),
                    child: const Text(
                      'Maintenance jobs are silent — no notifications, no escalation. Use for planned or routine work; the responsible team must pick it up from the list themselves.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
                if (jobType == JobType.building) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 30),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withValues(alpha: 120)),
                    ),
                    child: const Text(
                      'Building Maintenance jobs go directly to the maintenance team. No escalation.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
                if (jobType == JobType.specialist) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 30),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple.withValues(alpha: 120)),
                    ),
                    child: const Text(
                      'Pre Press Specialist jobs are auto-assigned to the specialist. Use only for Pre Press equipment.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
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
                      labelStyle: TextStyle(color: num == priority ? const Color(0xFFFF8C42) : onColor(priorityColors[num]), fontWeight: num == priority ? FontWeight.bold : FontWeight.normal),
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                    );
                  }),
                ),
                const SizedBox(height: 10),
                // Priority reference — shows only the selected level
                if (priority > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: priorityColors[priority].withValues(alpha: 30),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: priorityColors[priority].withValues(alpha: 120)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(color: priorityColors[priority], shape: BoxShape.circle),
                          child: Center(
                            child: Text('$priority', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            priorityDescriptions[priority],
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurface),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 20),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withValues(alpha: 70)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Describe the fault clearly:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                      SizedBox(height: 3),
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
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_isLoading || !_isOnline) ? null : _saveJobCard,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8C42),
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      textStyle: const TextStyle(fontSize: 24),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.black)
                        : Text(
                            _isOnline ? 'Save Job Card' : 'No connection — cannot submit',
                            style: TextStyle(color: Colors.black, fontSize: _isOnline ? 24 : 18),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
                 const Text('Photos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                 const SizedBox(height: 8),
                 ElevatedButton.icon(
                   // Always tappable — when the prerequisites are missing the tap
                   // explains itself instead of being a dead button.
                   onPressed: () {
                     if (part.isEmpty || description.isEmpty) {
                       ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(
                           content: Text('Fill in the part and description first — photos attach to the fault details.'),
                           backgroundColor: Colors.orange,
                         ),
                       );
                       return;
                     }
                     _addPhoto('Description');
                   },
                   icon: const Icon(Icons.add_a_photo),
                   label: const Text('Add Photo (Camera/Gallery)'),
                 ),
                 const SizedBox(height: 12),
                _buildPhotosPreview(),
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
                      _buildOfflineBanner(),
                      if (selectedDepartment != null || selectedArea != null || selectedMachine != null) ...[
                        Container(
                          padding: const EdgeInsets.only(left: 16, right: 4, top: 4, bottom: 4),
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
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: _clearSelections,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                visualDensity: VisualDensity.compact,
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
                               if (jobType == JobType.specialist && dept != 'Pre Press') {
                                 jobType = null;
                               }
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
                        children: _availableJobTypes.map((type) => ChoiceChip(
                          label: Text(type.displayName),
                          selected: jobType == type,
                          onSelected: (_) => setState(() => jobType = jobType == type ? null : type),
                          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                        )).toList(),
                      ),
                      if (jobType == JobType.maintenance) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 30),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.withValues(alpha: 120)),
                          ),
                          child: const Text(
                            'Maintenance jobs are silent — no notifications, no escalation. Use for planned or routine work; the responsible team must pick it up from the list themselves.',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
                      if (jobType == JobType.building) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 30),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.withValues(alpha: 120)),
                          ),
                          child: const Text(
                            'Building Maintenance jobs go directly to the maintenance team. No escalation.',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
                      if (jobType == JobType.specialist) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 30),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.purple.withValues(alpha: 120)),
                          ),
                          child: const Text(
                            'Pre Press Specialist jobs are auto-assigned to the specialist. Use only for Pre Press equipment.',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
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
                            labelStyle: TextStyle(color: num == priority ? const Color(0xFFFF8C42) : onColor(priorityColors[num]), fontWeight: num == priority ? FontWeight.bold : FontWeight.normal),
                            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                          );
                        }),
                      ),
                      const SizedBox(height: 8),
                      if (priority > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: priorityColors[priority].withValues(alpha: 30),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: priorityColors[priority].withValues(alpha: 120)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(color: priorityColors[priority], shape: BoxShape.circle),
                                child: Center(
                                  child: Text('$priority', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  priorityDescriptions[priority],
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurface),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 20),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.withValues(alpha: 70)),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Describe the fault clearly:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                            SizedBox(height: 3),
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
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: (_isLoading || !_isOnline) ? null : _saveJobCard,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF8C42),
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            textStyle: const TextStyle(fontSize: 24),
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(color: Colors.black)
                              : Text(
                                  _isOnline ? 'Save Job Card' : 'No connection — cannot submit',
                                  style: TextStyle(color: Colors.black, fontSize: _isOnline ? 24 : 18),
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text('Photos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        // Always tappable — when the prerequisites are missing
                        // the tap explains itself instead of being a dead button.
                        onPressed: () {
                          if (part.isEmpty || description.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Fill in the part and description first — photos attach to the fault details.'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }
                          _addPhoto('Description');
                        },
                        icon: const Icon(Icons.add_a_photo),
                        label: const Text('Add Photo (Camera/Gallery)'),
                      ),
                      const SizedBox(height: 12),
                      _buildPhotosPreview(),
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