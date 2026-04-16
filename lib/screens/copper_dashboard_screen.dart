import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/copper_provider.dart';        // ← ADD THIS LINE
import '../models/copper_inventory.dart';
import '../services/firestore_service.dart';
import 'sort_copper_screen.dart';
import 'copper_transactions_screen.dart';

class CopperDashboardScreen extends ConsumerStatefulWidget {
  const CopperDashboardScreen({super.key});

  @override
  ConsumerState<CopperDashboardScreen> createState() => _CopperDashboardScreenState();
}

class _CopperDashboardScreenState extends ConsumerState<CopperDashboardScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  
  final TextEditingController _addToSortKgController = TextEditingController();
  final TextEditingController _addToSortCommentsController = TextEditingController();
  final TextEditingController _plateBarsKgController = TextEditingController();
  final TextEditingController _plateBarsCommentsController = TextEditingController();
  final TextEditingController _useReuseKgController = TextEditingController();
  final TextEditingController _useReuseCommentsController = TextEditingController();
  final TextEditingController _recordSaleKgController = TextEditingController();
  final TextEditingController _recordSaleRPerKgController = TextEditingController();
  final TextEditingController _recordSaleCommentsController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String? _currentClockNo;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentClockNo().then((_) {
      // Temporarily skip password for testing
      setState(() => _isAuthenticated = true);
      // _showPasswordDialog();
    });
  }

  Future<void> _loadCurrentClockNo() async {
    _currentClockNo = await _firestoreService.getLoggedInEmployeeClockNo();
    setState(() {});
  }

  @override
  void dispose() {
    _addToSortKgController.dispose();
    _addToSortCommentsController.dispose();
    _plateBarsKgController.dispose();
    _plateBarsCommentsController.dispose();
    _useReuseKgController.dispose();
    _useReuseCommentsController.dispose();
    _recordSaleKgController.dispose();
    _recordSaleRPerKgController.dispose();
    _recordSaleCommentsController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showPasswordDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Enter Copper Password'),
        content: TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _authenticate,
            child: const Text('Enter'),
          ),
        ],
      ),
    );
  }

  Future<void> _authenticate() async {
    final entered = _passwordController.text;
    final correct = await _firestoreService.getCopperPassword();
    if (entered == correct) {
      setState(() => _isAuthenticated = true);
      _passwordController.clear();
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incorrect password'), backgroundColor: Colors.red));
    }
  }

  Future<void> _performAddToSort() async {
    final kg = double.tryParse(_addToSortKgController.text);
    if (kg == null || kg <= 0 || _currentClockNo == null) return;

    try {
      await 
      ref.read(copperNotifierProvider.notifier).performAddToSort(kg, _addToSortCommentsController.text, _currentClockNo!);
      _addToSortKgController.clear();
      _addToSortCommentsController.clear();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to sort')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _performPlateBars() async {
    final kg = double.tryParse(_plateBarsKgController.text);
    if (kg == null || kg <= 0 || _currentClockNo == null) return;

    try {
      await ref.read(copperNotifierProvider.notifier).performPlateBars(kg, _plateBarsCommentsController.text, _currentClockNo!);
      _plateBarsKgController.clear();
      _plateBarsCommentsController.clear();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plated bars')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _performUseReuse() async {
    final kg = double.tryParse(_useReuseKgController.text);
    if (kg == null || kg <= 0 || _currentClockNo == null) return;

    try {
      await ref.read(copperNotifierProvider.notifier).performUseReuse(kg, _useReuseCommentsController.text, _currentClockNo!);
      _useReuseKgController.clear();
      _useReuseCommentsController.clear();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Used reuse')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _performRecordSale() async {
    final kg = double.tryParse(_recordSaleKgController.text);
    final rPerKg = double.tryParse(_recordSaleRPerKgController.text);
    if (kg == null || kg <= 0 || rPerKg == null || rPerKg <= 0 || _currentClockNo == null) return;

    try {
      await ref.read(copperNotifierProvider.notifier).performRecordSale(kg, rPerKg, _recordSaleCommentsController.text, _currentClockNo!);
      _recordSaleKgController.clear();
      _recordSaleRPerKgController.clear();
      _recordSaleCommentsController.clear();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recorded sale')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  void _showAddToSortModal() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Add Copper to Sort', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: _addToSortKgController,
                decoration: const InputDecoration(labelText: 'Kg'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _addToSortCommentsController,
                decoration: const InputDecoration(labelText: 'Comments'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _performAddToSort,
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPlateBarsModal() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Plate Bars to Sell', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: _plateBarsKgController,
                decoration: const InputDecoration(labelText: 'Kg'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _plateBarsCommentsController,
                decoration: const InputDecoration(labelText: 'Comments'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _performPlateBars,
                child: const Text('Plate'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUseReuseModal() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Use Reuse', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: _useReuseKgController,
                decoration: const InputDecoration(labelText: 'Kg'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _useReuseCommentsController,
                decoration: const InputDecoration(labelText: 'Comments'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _performUseReuse,
                child: const Text('Use'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRecordSaleModal() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Record Sale', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: _recordSaleKgController,
                decoration: const InputDecoration(labelText: 'Kg'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _recordSaleRPerKgController,
                decoration: const InputDecoration(labelText: 'R per Kg'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _recordSaleCommentsController,
                decoration: const InputDecoration(labelText: 'Comments'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _performRecordSale,
                child: const Text('Record'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return const Scaffold(
        body: Center(child: Text('Authenticating...')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Copper Inventory'),
        backgroundColor: Colors.amber,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CopperTransactionsScreen())),
          ),
        ],
      ),
      body: StreamBuilder<CopperInventory>(
        stream: ref.watch(copperNotifierProvider.notifier).inventoryStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final inventory = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (inventory.sellKg > 400)
                  Container(
                    width: double.infinity,
                    color: Colors.red,
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 16),
                    child: const Text(
                      'Sell Bucket exceeds 400 kg – Contact client to sell',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: Card(
                        color: Colors.amber.shade100,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              const Text('Total Copper', style: TextStyle(fontSize: 14)),
                              Text('${inventory.totalKg.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Card(
                        color: Colors.orange.shade100,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              const Text('Est Value', style: TextStyle(fontSize: 14)),
                              Text('R ${inventory.estimatedValueR.toStringAsFixed(0)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Card(
                        color: Colors.brown.shade100,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              const Text('Sell Status', style: TextStyle(fontSize: 14)),
                              Text('${inventory.sellKg.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Inventory Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: BarChart(
                    BarChartData(
                      barGroups: [
                        BarChartGroupData(
                          x: 0,
                          barRods: [BarChartRodData(toY: inventory.sortKg, color: Colors.blue)],
                        ),
                        BarChartGroupData(
                          x: 1,
                          barRods: [BarChartRodData(toY: inventory.reuseKg, color: Colors.green)],
                        ),
                        BarChartGroupData(
                          x: 2,
                          barRods: [BarChartRodData(toY: inventory.sellKg, color: Colors.orange)],
                        ),
                      ],
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              switch (value.toInt()) {
                                case 0: return const Text('Sort', style: TextStyle(fontSize: 12));
                                case 1: return const Text('Reuse', style: TextStyle(fontSize: 12));
                                case 2: return const Text('Sell', style: TextStyle(fontSize: 12));
                                default: return const Text('');
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  children: [
                    Card(
                      color: Colors.blue.shade100,
                      child: InkWell(
                        onTap: _showAddToSortModal,
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add, size: 48, color: Colors.blue),
                              SizedBox(height: 8),
                              Text('Add to Sort', textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Card(
                      color: Colors.purple.shade100,
                      child: InkWell(
                        onTap: _showPlateBarsModal,
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.build, size: 48, color: Colors.purple),
                              SizedBox(height: 8),
                              Text('Plate Bars', textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Card(
                      color: Colors.green.shade100,
                      child: InkWell(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SortCopperScreen())),
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.sort, size: 48, color: Colors.green),
                              SizedBox(height: 8),
                              Text('Sort Copper', textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Card(
                      color: Colors.red.shade100,
                      child: InkWell(
                        onTap: _showUseReuseModal,
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.remove, size: 48, color: Colors.red),
                              SizedBox(height: 8),
                              Text('Use Reuse', textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Card(
                      color: Colors.amber.shade100,
                      child: InkWell(
                        onTap: _showRecordSaleModal,
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.sell, size: 48, color: Colors.amber),
                              SizedBox(height: 8),
                              Text('Record Sale', textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}