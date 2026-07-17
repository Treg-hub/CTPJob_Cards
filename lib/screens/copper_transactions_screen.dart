import 'package:flutter/material.dart';
import '../utils/persona_audit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/current_employee_provider.dart';
import '../services/copper_service.dart';
import '../models/copper_transaction.dart';
import '../utils/role.dart';
import '../utils/screen_insets.dart';

class CopperTransactionsScreen extends ConsumerStatefulWidget {
  const CopperTransactionsScreen({super.key});

  @override
  ConsumerState<CopperTransactionsScreen> createState() => _CopperTransactionsScreenState();
}

class _CopperTransactionsScreenState extends ConsumerState<CopperTransactionsScreen> {
  final CopperService _copperService = CopperService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _editCommentsController = TextEditingController();

  /// null = default last 90 days (never unbounded).
  DateTimeRange? _dateRange;
  String _searchQuery = '';

  DateTimeRange get _effectiveRange {
    if (_dateRange != null) return _dateRange!;
    final now = DateTime.now();
    return DateTimeRange(
      start: now.subtract(const Duration(days: 90)),
      end: now.add(const Duration(days: 1)),
    );
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() => _searchQuery = _searchController.text));
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
      // Back to default 90-day window (not full history).
      _dateRange = null;
      _searchController.clear();
    });
  }

  Future<void> _editComments(CopperTransaction tx) async {
    if (!guardPersonaSubmit(context)) return;
    final messenger = ScaffoldMessenger.of(context);
    _editCommentsController.text = tx.comments;
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
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
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final navigator = Navigator.of(sheetContext);
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
      case CopperTransaction.recordSale:
      case CopperTransaction.recordSaleFromWaste:
        return Icons.sell;
      case CopperTransaction.prepareForCollection:
        return Icons.inventory_2_outlined;
      case CopperTransaction.adjust:
        return Icons.tune;
      case CopperTransaction.zeroDust:
        return Icons.cleaning_services_outlined;
      default: return Icons.help;
    }
  }

  Color _getColorForType(String type) {
    switch (type) {
      case CopperTransaction.addToSort: return Colors.blue;
      case CopperTransaction.plateBars: return Colors.purple;
      case CopperTransaction.sort: return Colors.green;
      case CopperTransaction.useReuse: return Colors.red;
      case CopperTransaction.recordSale:
      case CopperTransaction.recordSaleFromWaste:
        return Colors.amber;
      case CopperTransaction.prepareForCollection:
        return Colors.orange;
      case CopperTransaction.adjust:
      case CopperTransaction.zeroDust:
        return Colors.blueGrey;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final employee = ref.watch(currentEmployeeProvider).valueOrNull;
    final isCopperAuth = isCopperAuthorized(employee);

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
                        ? 'Last 90 days (tap to pick range)'
                        : '${DateFormat('MM/dd').format(_dateRange!.start)} - ${DateFormat('MM/dd').format(_dateRange!.end)}'),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _clearFilters,
                  child: const Text('Reset 90d'),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<CopperTransaction>>(
              stream: _copperService.getTransactionsStream(range: _effectiveRange),
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
                  padding: ScreenInsets.listPadding(context, horizontal: 8, top: 4),
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
                              if (tx.rPerKg != null && isCopperAuth)
                                Text('R/kg: ${tx.rPerKg!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                              if (tx.totalValueR != null && isCopperAuth)
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
        ],
      ),
    );
  }
}
