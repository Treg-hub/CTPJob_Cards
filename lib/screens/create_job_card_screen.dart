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
  JobType jobType = JobType.mechanical;
  int priority = 3;
  String description = '';
  bool _isLoading = false;

  final FirestoreService _firestoreService = FirestoreService();

  String get operatorName => currentEmployee?.name ?? 'Unknown';

  Future<List<String>> _loadPreviousParts() async {
    if (selectedDepartment == null || selectedArea == null || selectedMachine == null) return [];
    return await _firestoreService.getPreviousParts(selectedDepartment!, selectedArea!, selectedMachine!);
  }

  Future<void> _saveJobCard() async {
    if (!_formKey.currentState!.validate()) return;
    if (selectedDepartment == null || selectedArea == null || selectedMachine == null || part.isEmpty) {
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
        type: jobType,
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
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Department', border: OutlineInputBorder()),
                    value: selectedDepartment,
                    items: data.keys.map((dept) => DropdownMenuItem(value: dept, child: Text(dept))).toList(),
                    onChanged: (val) => setState(() {
                      selectedDepartment = val;
                      selectedArea = null;
                      selectedMachine = null;
                      part = '';
                    }),
                    validator: (v) => v == null ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Area / Section', border: OutlineInputBorder()),
                    value: selectedArea,
                    items: areas.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                    onChanged: (val) => setState(() {
                      selectedArea = val;
                      selectedMachine = null;
                      part = '';
                    }),
                    validator: (v) => v == null ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Machine / Location', border: OutlineInputBorder()),
                    value: selectedMachine,
                    items: machines.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: (val) => setState(() {
                      selectedMachine = val;
                      part = '';
                    }),
                    validator: (v) => v == null ? 'Required' : null,
                  ),
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
                  const SizedBox(height: 24),
                  DropdownButtonFormField<JobType>(
                    decoration: const InputDecoration(labelText: 'Job Type', border: OutlineInputBorder()),
                    value: jobType,
                    items: JobType.values.map((type) => DropdownMenuItem(
                      value: type,
                      child: Text(type.displayName),
                    )).toList(),
                    onChanged: (val) => setState(() => jobType = val!),
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
                        backgroundColor: num >= 4 ? Colors.red : num == 3 ? Colors.orange : Colors.green,
                        selectedColor: Colors.white,
                        labelStyle: TextStyle(color: priority == num ? Colors.black : Colors.white),
                      );
                    }),
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
                        backgroundColor: Colors.orange,
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