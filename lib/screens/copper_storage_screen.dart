import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/copper_service.dart';
import '../services/firestore_service.dart';
import '../models/copper_transaction.dart';

class CopperStorageScreen extends StatefulWidget {
  const CopperStorageScreen({super.key});

  @override
  State<CopperStorageScreen> createState() => _CopperStorageScreenState();
}

class _CopperStorageScreenState extends State<CopperStorageScreen> {
  final CopperService _copperService = CopperService();
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _addKgController = TextEditingController();
  final TextEditingController _addDescController = TextEditingController();
  final TextEditingController _sortKgController = TextEditingController();
  final TextEditingController _removeKgController = TextEditingController();
  final TextEditingController _removeReasonController = TextEditingController();

  String? _currentClockNo;
  String? _selectedSortSubtype;
  String? _selectedRemoveSubtype;

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
    _addKgController.dispose();
    _addDescController.dispose();
    _sortKgController.dispose();
    _removeKgController.dispose();
    _removeReasonController.dispose();
    super.dispose();
  }

  Future<void> _addToSort() async {
    final kg = double.tryParse(_addKgController.text);
    if (kg == null || kg <= 0 || _currentClockNo == null) return;

    try {
      final tx = CopperTransaction(
        id: '',
        type: CopperType.toSort,
        kg: kg,
        clockNo: _currentClockNo!,
        timestamp: DateTime.now(),
        description: _addDescController.text.isEmpty ? null : _addDescController.text,
      );
      await _copperService.addTransaction(tx);
      _addKgController.clear();
      _addDescController.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to To Sort')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _sortCopper() async {
    final kg = double.tryParse(_sortKgController.text);
    if (kg == null || kg <= 0 || _selectedSortSubtype == null || _currentClockNo == null) return;

    // Check toSort total
    final toSortTotal = await _copperService.getTotalForType(CopperType.toSort);
    if (toSortTotal < kg) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not enough in To Sort'), backgroundColor: Colors.red));
      return;
    }

    CopperType targetType;
    if (_selectedSortSubtype == 'Nuggets') {
      targetType = CopperType.sellNuggets;
    } else if (_selectedSortSubtype == 'Rods') {
      targetType = CopperType.sellRods;
    } else {
      targetType = CopperType.reuse;
    }

    try {
      final tx = CopperTransaction(
        id: '',
        type: targetType,
        kg: kg,
        clockNo: _currentClockNo!,
        timestamp: DateTime.now(),
        description: 'Sorted from To Sort',
      );
      await _copperService.addTransaction(tx);
      _sortKgController.clear();
      _selectedSortSubtype = null;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sorted to $targetType')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _removeFromSell() async {
    final kg = double.tryParse(_removeKgController.text);
    if (kg == null || kg <= 0 || _selectedRemoveSubtype == null || _currentClockNo == null) return;

    CopperType soldType;
    if (_selectedRemoveSubtype == 'Nuggets') {
      soldType = CopperType.soldNuggets;
    } else {
      soldType = CopperType.soldRods;
    }

    try {
      final tx = CopperTransaction(
        id: '',
        type: soldType,
        kg: kg,
        clockNo: _currentClockNo!,
        timestamp: DateTime.now(),
        description: _removeReasonController.text.isEmpty ? 'Sold/Removed' : _removeReasonController.text,
      );
      await _copperService.addTransaction(tx);
      _removeKgController.clear();
      _removeReasonController.clear();
      _selectedRemoveSubtype = null;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Removed from Sell')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Copper Storage')),
      body: StreamBuilder<Map<CopperType, double>>(
        stream: _copperService.getTotalsStream(),
        builder: (context, totalsSnapshot) {
          if (!totalsSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final totals = totalsSnapshot.data!;
          final toSort = totals[CopperType.toSort] ?? 0.0;
          final reuse = totals[CopperType.reuse] ?? 0.0;
          final sellNuggets = totals[CopperType.sellNuggets] ?? 0.0;
          final sellRods = totals[CopperType.sellRods] ?? 0.0;
          final totalSell = sellNuggets + sellRods;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Bar Chart
                const Text('Current Amounts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: BarChart(
                    BarChartData(
                      barGroups: [
                        BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: toSort, color: Colors.blue)]),
                        BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: reuse, color: Colors.green)]),
                        BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: sellNuggets, color: Colors.orange)]),
                        BarChartGroupData(x: 3, barRods: [BarChartRodData(toY: sellRods, color: Colors.red)]),
                      ],
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              switch (value.toInt()) {
                                case 0: return const Text('To Sort');
                                case 1: return const Text('Reuse');
                                case 2: return const Text('Sell Nuggets');
                                case 3: return const Text('Sell Rods');
                                default: return const Text('');
                              }
                            },
                          ),
                        ),
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true)),
                      ),
                      borderData: FlBorderData(show: true),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Totals Cards
                Row(
                  children: [
                    Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(8), child: Text('To Sort: ${toSort.toStringAsFixed(1)}kg')))),
                    Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(8), child: Text('Reuse: ${reuse.toStringAsFixed(1)}kg')))),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(8), child: Text('Sell Nuggets: ${sellNuggets.toStringAsFixed(1)}kg')))),
                    Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(8), child: Text('Sell Rods: ${sellRods.toStringAsFixed(1)}kg')))),
                  ],
                ),
                Card(child: Padding(padding: const EdgeInsets.all(8), child: Text('Total Sell: ${totalSell.toStringAsFixed(1)}kg', style: TextStyle(color: totalSell > 400 ? Colors.red : Colors.black)))),
                const SizedBox(height: 16),
                // Add to To Sort
                const Text('Add to To Sort', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Expanded(child: TextField(controller: _addKgController, decoration: const InputDecoration(labelText: 'Kg'), keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: _addDescController, decoration: const InputDecoration(labelText: 'Description (optional)'))),
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: _addToSort, child: const Text('Add')),
                  ],
                ),
                const SizedBox(height: 16),
                // Sort Copper
                const Text('Sort Copper', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Expanded(child: TextField(controller: _sortKgController, decoration: const InputDecoration(labelText: 'Kg from To Sort'), keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedSortSubtype,
                        decoration: const InputDecoration(labelText: 'To'),
                        items: ['Reuse', 'Nuggets', 'Rods'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                        onChanged: (value) => setState(() => _selectedSortSubtype = value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: _sortCopper, child: const Text('Sort')),
                  ],
                ),
                const SizedBox(height: 16),
                // Remove from Sell
                const Text('Remove from Sell', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedRemoveSubtype,
                        decoration: const InputDecoration(labelText: 'Subtype'),
                        items: ['Nuggets', 'Rods'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                        onChanged: (value) => setState(() => _selectedRemoveSubtype = value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: _removeKgController, decoration: const InputDecoration(labelText: 'Kg'), keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: _removeReasonController, decoration: const InputDecoration(labelText: 'Reason (optional)'))),
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: _removeFromSell, child: const Text('Remove')),
                  ],
                ),
                const SizedBox(height: 16),
                // Transactions
                const Text('Recent Transactions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                StreamBuilder<List<CopperTransaction>>(
                  stream: _copperService.getTransactionsStream(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const CircularProgressIndicator();
                    final transactions = snapshot.data!.take(20).toList(); // Limit
                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: transactions.length,
                      itemBuilder: (context, index) {
                        final tx = transactions[index];
                        return Card(
                          child: ListTile(
                            leading: Icon(_getIconForType(tx.type), color: _getColorForType(tx.type)),
                            title: Text('${tx.type.name} - ${tx.kg}kg'),
                            subtitle: Text('${tx.clockNo} - ${tx.timestamp.toString().substring(0, 16)}'),
                            trailing: Text(tx.description ?? ''),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  IconData _getIconForType(CopperType type) {
    switch (type) {
      case CopperType.toSort: return Icons.sort;
      case CopperType.reuse: return Icons.refresh;
      case CopperType.sellNuggets: return Icons.sell;
      case CopperType.sellRods: return Icons.build;
      case CopperType.soldNuggets: return Icons.check_circle;
      case CopperType.soldRods: return Icons.check_circle;
    }
  }

  Color _getColorForType(CopperType type) {
    switch (type) {
      case CopperType.toSort: return Colors.blue;
      case CopperType.reuse: return Colors.green;
      case CopperType.sellNuggets: return Colors.orange;
      case CopperType.sellRods: return Colors.red;
      case CopperType.soldNuggets: return Colors.purple;
      case CopperType.soldRods: return Colors.purple;
    }
  }
}