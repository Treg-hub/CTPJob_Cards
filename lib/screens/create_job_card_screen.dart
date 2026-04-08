import 'package:flutter/material.dart';
import '../models/job_card.dart';
import '../services/firestore_service.dart';
import '../main.dart' show currentEmployee;

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

  String get operatorName => currentEmployee?.name ?? 'Unknown';

  Future<List<String>> _loadPreviousParts() async {
    if (selectedDepartment == null || selectedArea == null || selectedMachine == null) return [];
    return await _firestoreService.getPreviousParts(selectedDepartment!, selectedArea!, selectedMachine!);
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

  @override
  Widget build(BuildContext context) {
    debugPrint('Building CreateJobCardScreen - jobType: $jobType');
    return Scaffold(
      appBar: AppBar(title: const Text('Create Job Card')),
      body: Padding(
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
                  Text('Operator: $operatorName', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
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
                     )).toList(),
                   ),
                  if (selectedDepartment != null) ...[
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
                      )).toList(),
                    ),
                  ],
                  if (selectedArea != null) ...[
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
                    )).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Priority (1 = Low → 5 = Urgent)', style: TextStyle(fontWeight: FontWeight.bold)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(5, (i) {
                      final num = i + 1;
                      return ChoiceChip(
                        label: Text('$num'),
                        selected: priority == num,
                        onSelected: (_) => setState(() => priority = num),
                        backgroundColor: priorityColors[num],
                        selectedColor: priorityColors[num]?.withOpacity(0.2),
                        labelStyle: TextStyle(color: num == priority ? Colors.black87 : Colors.white, fontWeight: num == priority ? FontWeight.bold : FontWeight.normal),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  if (priority > 0)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: priorityColors[priority]?.withOpacity(0.1),
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
              );
            },
          ),
        ),
      ),
    );
  }
}