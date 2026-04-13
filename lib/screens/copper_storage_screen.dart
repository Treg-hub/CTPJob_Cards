import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
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

  final TextEditingController _addNuggetsKgController = TextEditingController();
  final TextEditingController _addNuggetsDescController = TextEditingController();
  final TextEditingController _addRodsKgController = TextEditingController();
  final TextEditingController _addRodsDescController = TextEditingController();
  final TextEditingController _sortKgController = TextEditingController();
  final TextEditingController _sellKgController = TextEditingController();
  final TextEditingController _sellReasonController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _sortingKgController = TextEditingController();
  final TextEditingController _sortedReuseKgController = TextEditingController();
  final TextEditingController _sortedSellKgController = TextEditingController();

  String? _currentClockNo;
  String? _selectedSortSubtype;
  String? _selectedSellSubtype;
  String _searchQuery = '';
  CopperType? _filterType;
  bool _myTransactionsOnly = false;
  bool _isAuthenticated = false;
  double _currentTotalSell = 0.0;

  @override
  void initState() {
    super.initState();
    _loadCurrentClockNo().then((_) => _showPasswordDialog());
  }

  Future<void> _loadCurrentClockNo() async {
    _currentClockNo = await _firestoreService.getLoggedInEmployeeClockNo();
    setState(() {});
  }

  @override
  void dispose() {
    _addNuggetsKgController.dispose();
    _addNuggetsDescController.dispose();
    _addRodsKgController.dispose();
    _addRodsDescController.dispose();
    _sortKgController.dispose();
    _sellKgController.dispose();
    _sellReasonController.dispose();
    _searchController.dispose();
    _passwordController.dispose();
    _sortingKgController.dispose();
    _sortedReuseKgController.dispose();
    _sortedSellKgController.dispose();
    super.dispose();
  }

  Future<void> _addNuggetsToSort() async {
    final kg = double.tryParse(_addNuggetsKgController.text);
    if (kg == null || kg <= 0 || _currentClockNo == null) return;

    try {
      final tx = CopperTransaction(
        id: '',
        type: CopperType.toSort,
        kg: kg,
        clockNo: _currentClockNo!,
        timestamp: DateTime.now(),
        description: _addNuggetsDescController.text.isEmpty ? null : _addNuggetsDescController.text,
      );
      await _copperService.addTransaction(tx);
      _addNuggetsKgController.clear();
      _addNuggetsDescController.clear();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added nuggets to To Sort')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _addRodsToSell() async {
    final kg = double.tryParse(_addRodsKgController.text);
    if (kg == null || kg <= 0 || _currentClockNo == null) return;

    try {
      final tx = CopperTransaction(
        id: '',
        type: CopperType.sellRods,
        kg: kg,
        clockNo: _currentClockNo!,
        timestamp: DateTime.now(),
        description: _addRodsDescController.text.isEmpty ? null : _addRodsDescController.text,
      );
      await _copperService.addTransaction(tx);
      _addRodsKgController.clear();
      _addRodsDescController.clear();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added rods to Sell Rods')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _sortCopper() async {
    final kg = double.tryParse(_sortKgController.text);
    if (kg == null || kg <= 0 || _selectedSortSubtype == null || _currentClockNo == null) return;

    final toSortTotal = await _copperService.getTotalForType(CopperType.toSort);
    if (toSortTotal < kg) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not enough in To Sort'), backgroundColor: Colors.red));
      return;
    }

    CopperType targetType;
    if (_selectedSortSubtype == 'Reuse') {
      targetType = CopperType.reuse;
    } else if (_selectedSortSubtype == 'Nuggets') {
      targetType = CopperType.sellNuggets;
    } else {
      targetType = CopperType.sellRods;
    }

    try {
      final tx = CopperTransaction(
        id: '',
        type: targetType,
        kg: kg,
        clockNo: _currentClockNo!,
        timestamp: DateTime.now(),
          description: 'Sorted from In Sorting',
      );
      await _copperService.addTransaction(tx);
      _sortKgController.clear();
      _selectedSortSubtype = null;
      Navigator.of(context).pop();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sorted to $targetType')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _sellFromSell() async {
    final kg = double.tryParse(_sellKgController.text);
    if (kg == null || kg <= 0 || _selectedSellSubtype == null || _currentClockNo == null) return;

    if (kg > _currentTotalSell) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot sell more than available'), backgroundColor: Colors.red));
      return;
    }

    CopperType soldType;
    if (_selectedSellSubtype == 'Nuggets') {
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
        description: _sellReasonController.text.isEmpty ? 'Sold/Removed' : _sellReasonController.text,
      );
      await _copperService.addTransaction(tx);
      _sellKgController.clear();
      _sellReasonController.clear();
      _selectedSellSubtype = null;
      Navigator.of(context).pop();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sold/Removed from Sell')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  void _showAddNuggetsModal() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Add Nuggets to To Sort', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: _addNuggetsKgController,
                decoration: const InputDecoration(labelText: 'Kg'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _addNuggetsDescController,
                decoration: const InputDecoration(labelText: 'Description (optional)'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _addNuggetsToSort,
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddRodsModal() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Add Rods to Sell Rods', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: _addRodsKgController,
                decoration: const InputDecoration(labelText: 'Kg'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _addRodsDescController,
                decoration: const InputDecoration(labelText: 'Description (optional)'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _addRodsToSell,
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSortModal() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Sort from To Sort', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: _sortKgController,
                decoration: const InputDecoration(labelText: 'Kg from To Sort'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedSortSubtype,
                decoration: const InputDecoration(labelText: 'To'),
                items: ['Reuse', 'Nuggets', 'Rods'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (value) => setState(() => _selectedSortSubtype = value),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _sortCopper,
                child: const Text('Sort'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSellModal() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Sell/Remove from Sell', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedSellSubtype,
                decoration: const InputDecoration(labelText: 'Subtype'),
                items: ['Nuggets', 'Rods'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (value) => setState(() => _selectedSellSubtype = value),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _sellKgController,
                decoration: const InputDecoration(labelText: 'Kg'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _sellReasonController,
                decoration: const InputDecoration(labelText: 'Reason (optional)'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _sellFromSell,
                child: const Text('Sell/Remove'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSellModalWithTotal() async {
    final totalSell = await _copperService.getTotalForType(CopperType.sellNuggets) + await _copperService.getTotalForType(CopperType.sellRods);
    _currentTotalSell = totalSell;
    _sellKgController.text = totalSell.toStringAsFixed(1);
    _showSellModal();
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

  void _showSortingModal() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Remove from To Sort to In Sorting', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: _sortingKgController,
                decoration: const InputDecoration(labelText: 'Kg to remove'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _sortingCopper,
                child: const Text('Remove'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sortingCopper() async {
    final kg = double.tryParse(_sortingKgController.text);
    if (kg == null || kg <= 0 || _currentClockNo == null) return;

    final toSortTotal = await _copperService.getTotalForType(CopperType.toSort);
    if (toSortTotal < kg) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not enough in To Sort'), backgroundColor: Colors.red));
      return;
    }

    try {
      final tx = CopperTransaction(
        id: '',
        type: CopperType.toSort,
        kg: -kg,
        clockNo: _currentClockNo!,
        timestamp: DateTime.now(),
        description: 'In Sorting',
      );
      await _copperService.addTransaction(tx);
      _sortingKgController.clear();
      Navigator.of(context).pop();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Removed from To Sort for Sorting')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  void _showSortedModal() {
    showModalBottomSheet(
      context: context,
      builder: (context) => FutureBuilder<CopperTransaction?>(
        future: _copperService.getLastSortingTransaction(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator());
          }
          final lastSorting = snapshot.data;
          if (lastSorting == null) {
            return const Padding(padding: EdgeInsets.all(16), child: Text('No recent Sorting transaction found.'));
          }
          final totalKg = lastSorting.kg;
          return StatefulBuilder(
            builder: (context, setState) => Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Split In Sorting to Reuse and To Sell (${totalKg}kg)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _sortedReuseKgController,
                    decoration: const InputDecoration(labelText: 'Kg to Reuse'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _sortedSellKgController,
                    decoration: const InputDecoration(labelText: 'Kg to Sell (Nuggets)'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _sortSortedCopper(totalKg),
                    child: const Text('Add Sorted'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _sortSortedCopper(double totalKg) async {
    final kgReuse = double.tryParse(_sortedReuseKgController.text) ?? 0.0;
    final kgSell = double.tryParse(_sortedSellKgController.text) ?? 0.0;
    if (kgReuse + kgSell != totalKg || _currentClockNo == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kg must sum to total from Sorting'), backgroundColor: Colors.red));
      return;
    }

    try {
      if (kgReuse > 0) {
        final txReuse = CopperTransaction(
          id: '',
          type: CopperType.reuse,
          kg: kgReuse,
          clockNo: _currentClockNo!,
          timestamp: DateTime.now(),
          description: 'Sorted from To Sort',
        );
        await _copperService.addTransaction(txReuse);
      }
      if (kgSell > 0) {
        final txSell = CopperTransaction(
          id: '',
          type: CopperType.sellNuggets,
          kg: kgSell,
          clockNo: _currentClockNo!,
          timestamp: DateTime.now(),
          description: 'Sorted from To Sort',
        );
        await _copperService.addTransaction(txSell);
      }
      _sortedReuseKgController.clear();
      _sortedSellKgController.clear();
      Navigator.of(context).pop();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added Sorted to Reuse and Sell')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
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
        title: const Text('Copper Storage'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 600;
          if (isDesktop) {
            return Row(
              children: [
                Expanded(child: _buildOverviewAndButtons()),
                Expanded(child: _buildTransactionsTab()),
              ],
            );
          } else {
            return Column(
              children: [
                Expanded(child: _buildOverviewAndButtons()),
                Expanded(child: _buildTransactionsTab()),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildOverviewAndButtons() {
    return StreamBuilder<List<CopperTransaction>>(
      stream: _copperService.getTransactionsStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final transactions = snapshot.data!;
        final totals = <CopperType, double>{};
        for (final tx in transactions) {
          totals[tx.type] = (totals[tx.type] ?? 0.0) + tx.kg;
        }
        final toSort = totals[CopperType.toSort] ?? 0.0;
        final reuse = totals[CopperType.reuse] ?? 0.0;
        final sellNuggets = totals[CopperType.sellNuggets] ?? 0.0;
        final sellRods = totals[CopperType.sellRods] ?? 0.0;
        final totalSell = sellNuggets + sellRods;
        final soldNuggets = totals[CopperType.soldNuggets] ?? 0.0;
        final soldRods = totals[CopperType.soldRods] ?? 0.0;
        final totalSold = soldNuggets + soldRods;
        final sortingTotal = transactions.where((tx) => tx.description == 'In Sorting').fold(0.0, (sum, tx) => sum + tx.kg);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              // Totals Cards
              Row(
                children: [
                  Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(4), child: Text('To Sort: ${toSort.toStringAsFixed(1)}kg', style: const TextStyle(fontSize: 14))))),
                  Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(4), child: Text('In Sorting: ${sortingTotal.toStringAsFixed(1)}kg', style: const TextStyle(fontSize: 14))))),
                ],
              ),
              Row(
                children: [
                  Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(4), child: Text('Reuse: ${reuse.toStringAsFixed(1)}kg', style: const TextStyle(fontSize: 14))))),
                  Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(4), child: Text('To Sell: ${totalSell.toStringAsFixed(1)}kg', style: const TextStyle(fontSize: 14))))),
                ],
              ),
              Card(child: Padding(padding: const EdgeInsets.all(4), child: Text('Sold: ${totalSold.toStringAsFixed(1)}kg', style: const TextStyle(fontSize: 14)))),
              const SizedBox(height: 8),
              // Bar Chart
              const Text('Storage Overview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SizedBox(
                height: 150,
                child: BarChart(
                  BarChartData(
                    barGroups: [
                      BarChartGroupData(
                        x: 0,
                        barRods: [BarChartRodData(toY: toSort, color: Colors.blue)],
                      ),
                      BarChartGroupData(
                        x: 1,
                        barRods: [BarChartRodData(toY: sortingTotal, color: Colors.purple)],
                      ),
                      BarChartGroupData(
                        x: 2,
                        barRods: [BarChartRodData(toY: reuse, color: Colors.green)],
                      ),
                      BarChartGroupData(
                        x: 3,
                        barRods: [BarChartRodData(toY: totalSell, color: Colors.orange)],
                      ),
                      BarChartGroupData(
                        x: 4,
                        barRods: [BarChartRodData(toY: totalSold, color: Colors.red)],
                      ),
                    ],
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            switch (value.toInt()) {
                              case 0: return const Text('To Sort', style: TextStyle(fontSize: 12));
                              case 1: return const Text('In Sorting', style: TextStyle(fontSize: 12));
                              case 2: return const Text('Reuse', style: TextStyle(fontSize: 12));
                              case 3: return const Text('To Sell', style: TextStyle(fontSize: 12));
                              case 4: return const Text('Sold', style: TextStyle(fontSize: 12));
                              default: return const Text('');
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _showAddNuggetsModal,
                    child: const Text('Add Nuggets', style: TextStyle(fontSize: 14)),
                  ),
                  ElevatedButton(
                    onPressed: _showAddRodsModal,
                    child: const Text('Add Rods', style: TextStyle(fontSize: 14)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _showSortingModal,
                    child: const Text('Remove to Sorting', style: TextStyle(fontSize: 14)),
                  ),
                  ElevatedButton(
                    onPressed: _showSortedModal,
                    child: const Text('Split Sorting', style: TextStyle(fontSize: 14)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _showSellModalWithTotal,
                child: const Text('Sell', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
        );
      },
    );
  }



  Widget _buildTransactionsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(labelText: 'Search', labelStyle: TextStyle(fontSize: 14)),
            style: const TextStyle(fontSize: 14),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        Wrap(
          spacing: 4,
          children: [
            FilterChip(
              label: const Text('My', style: TextStyle(fontSize: 12)),
              selected: _myTransactionsOnly,
              onSelected: (selected) => setState(() => _myTransactionsOnly = selected),
            ),
            ...CopperType.values.map((type) => FilterChip(
              label: Text(type.name, style: const TextStyle(fontSize: 12)),
              selected: _filterType == type,
              onSelected: (selected) => setState(() => _filterType = selected ? type : null),
            )),
          ],
        ),
        Expanded(
          child: StreamBuilder<List<CopperTransaction>>(
            stream: _copperService.getTransactionsStream(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const CircularProgressIndicator();
              final transactions = snapshot.data!.where((tx) {
                if (_myTransactionsOnly && tx.clockNo != _currentClockNo) return false;
                if (_filterType != null && tx.type != _filterType) return false;
                if (_searchQuery.isNotEmpty) {
                  final query = _searchQuery.toLowerCase();
                  return tx.clockNo.toLowerCase().contains(query) ||
                         tx.type.name.toLowerCase().contains(query) ||
                         (tx.description?.toLowerCase().contains(query) ?? false);
                }
                return true;
              }).take(50).toList();
              return ListView.separated(
                itemCount: transactions.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final tx = transactions[index];
                  return Card(
                    child: ListTile(
                      dense: true,
                      leading: Icon(_getIconForType(tx.type), color: _getColorForType(tx.type), size: 20),
                      title: Text('${tx.type.name} - ${tx.kg}kg', style: const TextStyle(fontSize: 14)),
                      subtitle: Text('${tx.clockNo} - ${DateFormat('MM/dd HH:mm').format(tx.timestamp)}', style: const TextStyle(fontSize: 12)),
                      trailing: Text(tx.description ?? '', style: const TextStyle(fontSize: 12)),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
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