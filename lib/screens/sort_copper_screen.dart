import 'package:flutter/material.dart';
import '../services/copper_service.dart';
import '../services/firestore_service.dart';

class SortCopperScreen extends StatefulWidget {
  const SortCopperScreen({super.key});

  @override
  State<SortCopperScreen> createState() => _SortCopperScreenState();
}

class _SortCopperScreenState extends State<SortCopperScreen> {
  final CopperService _copperService = CopperService();
  final FirestoreService _firestoreService = FirestoreService();

  final TextEditingController _reuseKgController = TextEditingController();
  final TextEditingController _sellKgController = TextEditingController();
  final TextEditingController _commentsController = TextEditingController();

  String? _currentClockNo;
  double _currentSortKg = 0.0;

  @override
  void initState() {
    super.initState();
    _loadCurrentClockNo();
  }

  Future<void> _loadCurrentClockNo() async {
    _currentClockNo = await _firestoreService.getLoggedInEmployeeClockNo();
    setState(() {});
  }

  @override
  void dispose() {
    _reuseKgController.dispose();
    _sellKgController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  double get _reuseKg => double.tryParse(_reuseKgController.text) ?? 0.0;
  double get _sellKg => double.tryParse(_sellKgController.text) ?? 0.0;
  double get _totalInput => _reuseKg + _sellKg;
  bool get _isValid => _totalInput == _currentSortKg && _currentSortKg > 0;

  Future<void> _performSort() async {
    if (!_isValid || _currentClockNo == null) return;

    try {
      await _copperService.performSort(_reuseKg, _sellKg, _commentsController.text, _currentClockNo!);
      _reuseKgController.clear();
      _sellKgController.clear();
      _commentsController.clear();
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Success'),
          content: const Text('Copper sorted successfully.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      ).then((_) => Navigator.of(context).pop());
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sort Copper'),
        backgroundColor: Colors.amber,
      ),
      body: StreamBuilder(
        stream: _copperService.getInventoryStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          _currentSortKg = snapshot.data!.sortKg;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Card(
                  color: Colors.blue.shade100,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text('Current Sort Bucket', style: TextStyle(fontSize: 16)),
                        Text('${_currentSortKg.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _reuseKgController,
                  decoration: const InputDecoration(labelText: 'Kg to Reuse'),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => setState(() {}),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _sellKgController,
                  decoration: const InputDecoration(labelText: 'Kg to Sell'),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => setState(() {}),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _commentsController,
                  decoration: const InputDecoration(labelText: 'Comments'),
                ),
                const SizedBox(height: 16),
                if (_totalInput != _currentSortKg)
                  Text(
                    'Sum (${_totalInput.toStringAsFixed(1)} kg) must equal sort bucket (${_currentSortKg.toStringAsFixed(1)} kg)',
                    style: const TextStyle(color: Colors.red),
                  ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isValid ? _performSort : null,
                  child: const Text('Confirm Sort'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}