import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import '../providers/copper_provider.dart';
import '../models/copper_inventory.dart';
import '../models/copper_transaction.dart';
import '../services/copper_service.dart';
import '../services/firestore_service.dart';

class CopperDashboardScreen extends ConsumerStatefulWidget {
  const CopperDashboardScreen({super.key});

  @override
  ConsumerState<CopperDashboardScreen> createState() => _CopperDashboardScreenState();
}

class _CopperDashboardScreenState extends ConsumerState<CopperDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final CopperService _copperService = CopperService();
  final FirestoreService _firestoreService = FirestoreService();
  String? _currentClockNo;
  bool _isLoading = false;

  // Transaction form controllers
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _rPerKgController = TextEditingController();
  final TextEditingController _commentsController = TextEditingController();
  String _selectedType = 'addToSort';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadClockNo();
  }

  Future<void> _loadClockNo() async {
    _currentClockNo = await _firestoreService.getLoggedInEmployeeClockNo();
    setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _amountController.dispose();
    _rPerKgController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  Future<void> _executeTransaction() async {
    if (_currentClockNo == null) return;
    final amount = double.tryParse(_amountController.text) ?? 0;
    final rPerKg = double.tryParse(_rPerKgController.text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Amount must be greater than 0')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final notifier = ref.read(copperNotifierProvider.notifier);
      switch (_selectedType) {
        case 'addToSort':
          await notifier.performAddToSort(amount, _commentsController.text, _currentClockNo!);
          break;
        case 'plateBars':
          await notifier.performPlateBars(amount, _commentsController.text, _currentClockNo!);
          break;
        case 'useReuse':
          await notifier.performUseReuse(amount, _commentsController.text, _currentClockNo!);
          break;
        case 'recordSale':
          if (rPerKg <= 0) throw Exception('R/kg required for sale');
          await notifier.performRecordSale(amount, rPerKg, _commentsController.text, _currentClockNo!);
          break;
      }
      _amountController.clear();
      _rPerKgController.clear();
      _commentsController.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction successful ✅')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportCSV(List<CopperTransaction> transactions) async {
    if (transactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No transactions to export')));
      return;
    }

    final csvRows = <List<dynamic>>[
      ['Timestamp', 'Type', 'Amount (kg)', 'From', 'To', 'R/kg', 'Comments'],
    ];

    for (var tx in transactions) {
      csvRows.add([
        DateFormat('yyyy-MM-dd HH:mm:ss').format(tx.timestamp.toDate()),
        tx.type,
        tx.amountKg,
        tx.fromBucket ?? '',
        tx.toBucket ?? '',
        tx.rPerKg ?? '',
        tx.comments,
      ]);
    }

    final csvString = const ListToCsvConverter().convert(csvRows);
    await Clipboard.setData(ClipboardData(text: csvString));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ CSV copied to clipboard – paste into Excel!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Copper Management'),
        backgroundColor: Colors.amber,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.swap_horiz), text: 'Make Transaction'),
            Tab(icon: Icon(Icons.history), text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ==================== TAB 1: MAKE TRANSACTION ====================
          ref.watch(copperNotifierProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(child: Text('Error: $error')),
            data: (inv) {

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Current Copper Buckets', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildBucketCard('Sort', inv.sortKg, Colors.blue, Icons.sort),
                        const SizedBox(width: 8),
                        _buildBucketCard('Reuse', inv.reuseKg, Colors.green, Icons.refresh),
                        const SizedBox(width: 8),
                        _buildBucketCard('Sell', inv.sellKg, Colors.amber, Icons.sell),
                      ],
                    ),
                    const SizedBox(height: 32),
                    const Text('New Transaction', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedType,
                      decoration: const InputDecoration(labelText: 'Transaction Type'),
                      items: const [
                        DropdownMenuItem(value: 'addToSort', child: Text('Add to Sort (from baths)')),
                        DropdownMenuItem(value: 'plateBars', child: Text('Plate Bars to Sell')),
                        DropdownMenuItem(value: 'useReuse', child: Text('Use from Reuse')),
                        DropdownMenuItem(value: 'recordSale', child: Text('Record Sale')),
                      ],
                      onChanged: (v) => setState(() => _selectedType = v!),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amountController,
                      decoration: const InputDecoration(labelText: 'Amount (kg)'),
                      keyboardType: TextInputType.number,
                    ),
                    if (_selectedType == 'recordSale') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _rPerKgController,
                        decoration: const InputDecoration(labelText: 'R per kg'),
                        keyboardType: TextInputType.number,
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _commentsController,
                      decoration: const InputDecoration(labelText: 'Comments'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _executeTransaction,
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Execute Transaction', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // ==================== TAB 2: HISTORY ====================
          StreamBuilder<List<CopperTransaction>>(
            stream: _copperService.getTransactionsStream(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final txs = snapshot.data!;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.download),
                      label: const Text('Export CSV'),
                      onPressed: () => _exportCSV(txs),
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async => setState(() {}),
                      child: ListView.separated(
                        itemCount: txs.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, index) {
                          final tx = txs[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: ListTile(
                              leading: Icon(_getIcon(tx.type), color: _getColor(tx.type)),
                              title: Text('${tx.type.toUpperCase()} • ${tx.amountKg.toStringAsFixed(1)} kg'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (tx.fromBucket != null || tx.toBucket != null)
                                    Text('${tx.fromBucket ?? ''} → ${tx.toBucket ?? ''}'),
                                  if (tx.rPerKg != null) Text('R/kg: ${tx.rPerKg!.toStringAsFixed(2)}'),
                                  Text(tx.comments, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                              trailing: Text(DateFormat('dd/MM HH:mm').format(tx.timestamp.toDate())),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBucketCard(String title, double kg, Color color, IconData icon) {
    return Expanded(
      child: Card(
        color: color.withOpacity(0.1),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${kg.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (kg / 500).clamp(0.0, 1.0),
                backgroundColor: Colors.grey[300],
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIcon(String type) {
    switch (type) {
      case CopperTransaction.addToSort: return Icons.add_circle;
      case CopperTransaction.plateBars: return Icons.build_circle;
      case CopperTransaction.sort: return Icons.sort;
      case CopperTransaction.useReuse: return Icons.remove_circle;
      case CopperTransaction.recordSale: return Icons.attach_money;
      default: return Icons.help;
    }
  }

  Color _getColor(String type) {
    switch (type) {
      case CopperTransaction.addToSort: return Colors.blue;
      case CopperTransaction.plateBars: return Colors.purple;
      case CopperTransaction.sort: return Colors.green;
      case CopperTransaction.useReuse: return Colors.red;
      case CopperTransaction.recordSale: return Colors.amber;
      default: return Colors.grey;
    }
  }
}