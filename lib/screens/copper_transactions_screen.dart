import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/copper_service.dart';
import '../services/firestore_service.dart';
import '../models/copper_transaction.dart';

class CopperTransactionsScreen extends StatefulWidget {
  const CopperTransactionsScreen({super.key});

  @override
  State<CopperTransactionsScreen> createState() => _CopperTransactionsScreenState();
}

class _CopperTransactionsScreenState extends State<CopperTransactionsScreen> {
  final CopperService _copperService = CopperService();
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _editCommentsController = TextEditingController();

  String? _currentClockNo;
  bool _isGPeens = false;

  DateTimeRange? _dateRange;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() => _searchQuery = _searchController.text));
    _loadCurrentClockNo();
  }

  Future<void> _loadCurrentClockNo() async {
    _currentClockNo = await _firestoreService.getLoggedInEmployeeClockNo();
    _isGPeens = _currentClockNo == '22';
    setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    _editCommentsController.dispose();
    super.dispose();
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
    }
  }

  void _clearFilters() {
    setState(() {
      _dateRange = null;
      _searchController.clear();
    });
  }

  Future<void> _editComments(CopperTransaction tx) async {
    _editCommentsController.text = tx.comments;
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Edit Comments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: _editCommentsController,
                decoration: const InputDecoration(labelText: 'Comments'),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await _copperService.updateTransactionComments(tx.id, _editCommentsController.text);
                        navigator.pop();
                        messenger.showSnackBar(const SnackBar(content: Text('Comments updated')));
                      } catch (e) {
                        messenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case CopperTransaction.addToSort: return Icons.add;
      case CopperTransaction.plateBars: return Icons.build;
      case CopperTransaction.sort: return Icons.sort;
      case CopperTransaction.useReuse: return Icons.remove;
      case CopperTransaction.recordSale: return Icons.sell;
      default: return Icons.help;
    }
  }

  Color _getColorForType(String type) {
    switch (type) {
      case CopperTransaction.addToSort: return Colors.blue;
      case CopperTransaction.plateBars: return Colors.purple;
      case CopperTransaction.sort: return Colors.green;
      case CopperTransaction.useReuse: return Colors.red;
      case CopperTransaction.recordSale: return Colors.amber;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Copper Transactions'),
        backgroundColor: Colors.amber,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search comments and type',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _selectDateRange,
                    child: Text(_dateRange == null
                        ? 'Select Date Range'
                        : '${DateFormat('MM/dd').format(_dateRange!.start)} - ${DateFormat('MM/dd').format(_dateRange!.end)}'),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _clearFilters,
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => setState(() {}),
              child: StreamBuilder<List<CopperTransaction>>(
                stream: _copperService.getTransactionsStream(range: _dateRange),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final transactions = snapshot.data!.where((tx) {
                    if (_searchQuery.isNotEmpty) {
                      final query = _searchQuery.toLowerCase();
                      return tx.comments.toLowerCase().contains(query) || tx.type.toLowerCase().contains(query);
                    }
                    return true;
                  }).toList();
                  return ListView.separated(
                    itemCount: transactions.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final tx = transactions[index];
                      return Card(
                        child: InkWell(
                          onTap: () => _editComments(tx),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(_getIconForType(tx.type), color: _getColorForType(tx.type)),
                                    const SizedBox(width: 8),
                                    Text(DateFormat('MM/dd HH:mm').format(tx.timestamp.toDate()), style: const TextStyle(fontSize: 12)),
                                    const Spacer(),
                                    Text('${tx.amountKg.toStringAsFixed(1)} kg', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(tx.type, style: const TextStyle(fontSize: 14)),
                                if (tx.fromBucket != null || tx.toBucket != null)
                                  Text('${tx.fromBucket ?? ''} → ${tx.toBucket ?? ''}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                if (tx.rPerKg != null && _isGPeens)
                                  Text('R/kg: ${tx.rPerKg!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                                if (tx.totalValueR != null && _isGPeens)
                                  Text('Total: R ${tx.totalValueR!.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12)),
                                const SizedBox(height: 4),
                                Text(tx.comments, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}