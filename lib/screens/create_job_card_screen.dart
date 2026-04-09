import 'package:flutter/material.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
import '../main.dart' show currentEmployee;
import 'job_card_detail_screen.dart';
import 'view_job_cards_screen.dart';

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
  JobType? jobType;
  int priority = 3;
  String description = '';
  bool _isLoading = false;

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
    "External issue: No runnability impact",
    "Minimal interference: Can run",
    "Reduced speed: No waste impact",
    "Reduced speed: Causes additional waste",
    "Cannot run: Requires urgent attention",
  ];

  final FirestoreService _firestoreService = FirestoreService();

  bool get _isWide => MediaQuery.of(context).size.width >= 1000;

  Color _getPriorityColor(String priority) {
    final num = int.tryParse(priority.substring(1)) ?? 0;
    switch (num) {
      case 1: return Colors.green[500]!;
      case 2: return Colors.lightGreen[500]!;
      case 3: return Colors.amber[500]!;
      case 4: return Colors.deepOrange[500]!;
      case 5: return Colors.red[700]!;
      default: return Colors.grey;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open': return Colors.blue;
      case 'completed': return Colors.green;
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
      );

      await _firestoreService.createJobCard(jobCard);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Job Card saved!'), backgroundColor: Colors.green),
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
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
          );
        }

        return Column(
          children: [
            Text(path.isEmpty ? 'Select department to see previous jobs' : 'Previous jobs for $path', style: const TextStyle(fontWeight: FontWeight.bold)),
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
                            Row(
                              children: [
                            Text(
                              '${job.department} > ${job.machine} > ${job.area}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                                const SizedBox(width: 8),
                                Text(
                                  'Created by: ${job.operator}',
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
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
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(job.status.name).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    job.status.displayName,
                                    style: TextStyle(color: _getStatusColor(job.status.name), fontSize: 11, fontWeight: FontWeight.w500),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blueGrey.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    job.type.displayName,
                                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                   job.assignedNames?.join(', ') ?? 'Unassigned',
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
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
                      color: const Color.fromARGB(255, 36, 36, 36),
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
                  const SizedBox(height: 16),
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
                         labelStyle: selectedDepartment == dept ? const TextStyle(color: Color(0xFFFF8C42)) : const TextStyle(color: Colors.white),
                       )).toList(),
                   ),
                 ],
                if (selectedDepartment != null && selectedArea == null) ...[
                   const SizedBox(height: 16),
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
                       labelStyle: selectedArea == area ? const TextStyle(color: Color(0xFFFF8C42)) : const TextStyle(color: Colors.white),
                     )).toList(),
                   ),
                 ],
                if (selectedArea != null && selectedMachine == null) ...[
                   const SizedBox(height: 16),
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
                       labelStyle: selectedMachine == machine ? const TextStyle(color: Color(0xFFFF8C42)) : const TextStyle(color: Colors.white),
                     )).toList(),
                   ),
                 ],
                if (selectedMachine != null) ...[
                  const SizedBox(height: 16),
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
                                onPressed: () => setState(() => part = p),
                              )).toList(),
                            ),
                          const SizedBox(height: 8),
                          TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'Type part or tap suggestion above',
                              border: OutlineInputBorder(),
                            ),
                            initialValue: part,
                            onChanged: (v) => part = v,
                            validator: (v) => v!.isEmpty ? 'Required' : null,
                          ),
                        ],
                      );
                    },
                  ),
                ],
                const SizedBox(height: 24),
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
                    labelStyle: jobType == type ? const TextStyle(color: Color(0xFFFF8C42)) : const TextStyle(color: Colors.white),
                  )).toList(),
                ),
                const SizedBox(height: 16),
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
                      selectedColor: priorityColors[num].withOpacity(0.2),
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
                      color: priorityColors[priority].withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      priorityDescriptions[priority],
                      style: TextStyle(
                        color: priorityColors[priority],
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 24),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Job Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 4,
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                  onChanged: (v) => description = v,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveJobCard,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFFF8C42),
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      textStyle: const TextStyle(fontSize: 24),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.black)
                        : const Text('Save Job Card'),
                  ),
                ),
                const SizedBox(height: 24),
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
                            color: const Color.fromARGB(255, 36, 36, 36),
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
                        const SizedBox(height: 16),
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
                         const SizedBox(height: 16),
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
                         const SizedBox(height: 16),
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
                        const SizedBox(height: 24),
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
                                      onPressed: () => setState(() => part = p),
                                    )).toList(),
                                  ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  decoration: const InputDecoration(
                                    labelText: 'Type part or tap suggestion above',
                                    border: OutlineInputBorder(),
                                  ),
                                  initialValue: part,
                                  onChanged: (v) => part = v,
                                  validator: (v) => v!.isEmpty ? 'Required' : null,
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 24),
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
                      const SizedBox(height: 16),
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
                            selectedColor: priorityColors[num].withOpacity(0.2),
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
                            color: priorityColors[priority].withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            priorityDescriptions[priority],
                            style: TextStyle(
                              color: priorityColors[priority],
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      const SizedBox(height: 24),
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Job Description',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 4,
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                        onChanged: (v) => description = v,
                      ),
                      const SizedBox(height: 40),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _saveJobCard,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFFF8C42),
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            textStyle: const TextStyle(fontSize: 24),
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(color: Colors.black)
                              : const Text('Save Job Card'),
                        ),
                      ),
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
            child: Text('Operator: $operatorName', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _isWide ? _buildWideLayout() : _buildNarrowLayout(),
    );
  }
}