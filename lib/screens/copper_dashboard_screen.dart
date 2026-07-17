import 'package:flutter/material.dart';
import '../utils/persona_audit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import '../models/waste_stock_source.dart';
import '../providers/copper_provider.dart';
import '../providers/current_employee_provider.dart';
import '../models/copper_inventory.dart';
import '../models/copper_transaction.dart';
import '../services/copper_service.dart';
import '../utils/role.dart';
import '../utils/screen_insets.dart';
import 'waste_stock_inventory_screen.dart';

class CopperDashboardScreen extends ConsumerStatefulWidget {
  const CopperDashboardScreen({
    super.key,
    /// When embedded in Home shell, switch to the Waste tab (preferred).
    this.onOpenWaste,
  });

  final VoidCallback? onOpenWaste;

  @override
  ConsumerState<CopperDashboardScreen> createState() =>
      _CopperDashboardScreenState();
}

class _CopperDashboardScreenState extends ConsumerState<CopperDashboardScreen>
    with SingleTickerProviderStateMixin {
  static const double _bucketMaxKg = 500;
  static const _decimalKeyboard =
      TextInputType.numberWithOptions(decimal: true);

  late TabController _tabController;
  final CopperService _copperService = CopperService();
  bool _isLoading = false;

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _reuseKgController = TextEditingController();
  final TextEditingController _sellKgController = TextEditingController();
  final TextEditingController _commentsController = TextEditingController();
  String _selectedType = 'addToSort';

  double get _sortTotal =>
      CopperService.roundKg(
        (double.tryParse(_reuseKgController.text) ?? 0) +
            (double.tryParse(_sellKgController.text) ?? 0),
      );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _amountController.dispose();
    _reuseKgController.dispose();
    _sellKgController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  void _fillAmount(double kg) {
    _amountController.text = CopperService.roundKg(kg).toStringAsFixed(1);
    setState(() {});
  }

  String _typeHelp(String type) {
    switch (type) {
      case 'addToSort':
        return 'Copper scraped from baths → To Sort bucket.';
      case 'plateBars':
        return 'Plate bars go straight to To Sell (rods). At '
            '${kCopperWasteStockThresholdKg.toStringAsFixed(0)} kg total sell, '
            'waste stock is auto-created for collection.';
      case 'removeFromSort':
        return 'Enter how much goes to Reuse (back to process) and how much to '
            'Sell (nuggets). Total is taken from To Sort.';
      case 'useReuse':
        return 'Take copper from To Reuse (returned to baths / used). '
            'Use “All” for a stuck remainder like 0.1 kg.';
      default:
        return '';
    }
  }

  void _openWaste() {
    if (widget.onOpenWaste != null) {
      widget.onOpenWaste!();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WasteStockInventoryScreen()),
    );
  }

  Future<void> _executeTransaction() async {
    if (!guardPersonaSubmit(context)) return;
    final employee = ref.read(currentEmployeeProvider).valueOrNull;
    if (employee == null) return;
    final actor = resolveWriteActor(employee)!;
    final inv = ref.read(copperNotifierProvider).valueOrNull;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _isLoading = true);
    try {
      final notifier = ref.read(copperNotifierProvider.notifier);

      if (_selectedType == 'removeFromSort') {
        final reuse =
            CopperService.roundKg(double.tryParse(_reuseKgController.text) ?? 0);
        final sell =
            CopperService.roundKg(double.tryParse(_sellKgController.text) ?? 0);
        final total = CopperService.roundKg(reuse + sell);
        if (reuse < 0 || sell < 0) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Amounts cannot be negative')),
          );
          return;
        }
        if (total <= 0) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Enter reuse and/or sell kg greater than 0')),
          );
          return;
        }
        final sortKg = inv?.sortKg ?? 0;
        if (!CopperService.hasEnoughKg(sortKg, total)) {
          messenger.showSnackBar(SnackBar(
            content: Text(
              'Cannot remove ${total.toStringAsFixed(1)} kg — only '
              '${CopperService.roundKg(sortKg).toStringAsFixed(1)} kg in sort',
            ),
          ));
          return;
        }
        await notifier.performSort(
          reuse,
          sell,
          _commentsController.text,
          actor.clockNo,
        );
      } else {
        final amount =
            CopperService.roundKg(double.tryParse(_amountController.text) ?? 0);
        if (amount <= 0) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Amount must be greater than 0')),
          );
          return;
        }
        if (_selectedType == 'useReuse') {
          final reuseKg = inv?.reuseKg ?? 0;
          if (!CopperService.hasEnoughKg(reuseKg, amount)) {
            messenger.showSnackBar(SnackBar(
              content: Text(
                'Cannot use ${amount.toStringAsFixed(1)} kg — only '
                '${CopperService.roundKg(reuseKg).toStringAsFixed(1)} kg in reuse',
              ),
            ));
            return;
          }
          await notifier.performUseReuse(
            amount,
            _commentsController.text,
            actor.clockNo,
          );
        } else if (_selectedType == 'addToSort') {
          await notifier.performAddToSort(
            amount,
            _commentsController.text,
            actor.clockNo,
          );
        } else if (_selectedType == 'plateBars') {
          await notifier.performPlateBars(
            amount,
            _commentsController.text,
            actor.clockNo,
          );
        }
      }

      _amountController.clear();
      _reuseKgController.clear();
      _sellKgController.clear();
      _commentsController.clear();
      messenger.showSnackBar(
        const SnackBar(content: Text('Transaction successful ✅')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _zeroDust() async {
    if (!guardPersonaSubmit(context)) return;
    final employee = ref.read(currentEmployeeProvider).valueOrNull;
    if (employee == null || !isAdmin(employee)) return;
    final actor = resolveWriteActor(employee)!;
    final commentsCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zero dust (≤ 0.1 kg)'),
        content: TextField(
          controller: commentsCtrl,
          decoration: const InputDecoration(
            labelText: 'Reason (required)',
            hintText: 'e.g. Clear float remainder',
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Zero')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(copperNotifierProvider.notifier).performZeroDust(
            comments: commentsCtrl.text,
            clockNo: actor.clockNo,
          );
      messenger.showSnackBar(const SnackBar(content: Text('Dust cleared ✅')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      commentsCtrl.dispose();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _adjustBucket(CopperInventory inv) async {
    if (!guardPersonaSubmit(context)) return;
    final employee = ref.read(currentEmployeeProvider).valueOrNull;
    if (employee == null || !isAdmin(employee)) return;
    final actor = resolveWriteActor(employee)!;
    var bucket = 'reuse';
    final deltaCtrl = TextEditingController();
    final commentsCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Adjust bucket'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: bucket,
                decoration: const InputDecoration(labelText: 'Bucket'),
                items: const [
                  DropdownMenuItem(value: 'sort', child: Text('To Sort')),
                  DropdownMenuItem(value: 'reuse', child: Text('To Reuse')),
                  DropdownMenuItem(value: 'sell', child: Text('To Sell')),
                ],
                onChanged: (v) => setLocal(() => bucket = v ?? 'reuse'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: deltaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Delta (kg)',
                  helperText: 'Positive adds, negative removes',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentsCtrl,
                decoration: const InputDecoration(labelText: 'Reason (required)'),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final delta = double.tryParse(deltaCtrl.text) ?? 0;
    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(copperNotifierProvider.notifier).performAdjust(
            bucket: bucket,
            deltaKg: delta,
            comments: commentsCtrl.text,
            clockNo: actor.clockNo,
          );
      messenger.showSnackBar(const SnackBar(content: Text('Adjust saved ✅')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      deltaCtrl.dispose();
      commentsCtrl.dispose();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _exportCSV(List<CopperTransaction> transactions) async {
    if (transactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No transactions to export')),
      );
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
        tx.rPerKg?.toString() ?? '',
        tx.comments,
      ]);
    }

    final csvString = CsvEncoder().convert(csvRows);
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: csvString));

    messenger.showSnackBar(
      const SnackBar(content: Text('✅ CSV copied to clipboard – paste into Excel!')),
    );
  }

  Widget _buildStatusCard(CopperInventory inv, ColorScheme scheme) {
    final threshold = kCopperWasteStockThresholdKg;
    final sell = CopperService.roundKg(inv.sellKg);
    final progress = (sell / threshold).clamp(0.0, 1.0);
    final batchOpen = inv.activeCopperWasteBatchId != null &&
        inv.activeCopperWasteBatchId!.isNotEmpty;
    final show = sell > 0 || batchOpen;
    if (!show) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Collection status',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              batchOpen
                  ? 'Waste batch open — collect via Waste (sales record on load complete).'
                  : 'To Sell: ${sell.toStringAsFixed(1)} / ${threshold.toStringAsFixed(0)} kg '
                      'until auto waste stock',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            if (!batchOpen) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: scheme.surfaceContainerHighest,
                color: Colors.amber.shade700,
              ),
            ],
            if (inv.sellRodsKg > 0 || inv.sellNuggetsKg > 0) ...[
              const SizedBox(height: 6),
              Text(
                'Rods ${CopperService.roundKg(inv.sellRodsKg).toStringAsFixed(1)} kg · '
                'Nuggets ${CopperService.roundKg(inv.sellNuggetsKg).toStringAsFixed(1)} kg',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _openWaste,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Open Waste'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionTab() {
    final employee = ref.watch(currentEmployeeProvider).valueOrNull;
    final admin = isAdmin(employee);
    final scheme = Theme.of(context).colorScheme;

    return ref.watch(copperNotifierProvider).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
      data: (CopperInventory inv) {
        final hasDust = CopperService.isDustKg(inv.sortKg) ||
            CopperService.isDustKg(inv.reuseKg) ||
            CopperService.isDustKg(inv.sellKg) ||
            CopperService.isDustKg(inv.sellRodsKg) ||
            CopperService.isDustKg(inv.sellNuggetsKg);

        return SingleChildScrollView(
          padding: ScreenInsets.symmetricScroll(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current Copper Buckets',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildBucketCard('To Sort', inv.sortKg, Colors.blue, Icons.sort),
                  const SizedBox(width: 8),
                  _buildBucketCard(
                      'To Reuse', inv.reuseKg, Colors.green, Icons.refresh),
                  const SizedBox(width: 8),
                  _buildBucketCard('To Sell', inv.sellKg, Colors.amber, Icons.sell),
                ],
              ),
              _buildStatusCard(inv, scheme),
              const SizedBox(height: 12),
              Material(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    'Sales are recorded when a Copper Waste load is completed — '
                    'not from this screen.',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
              if (admin) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : () => _adjustBucket(inv),
                      icon: const Icon(Icons.tune, size: 18),
                      label: const Text('Adjust'),
                    ),
                    if (hasDust)
                      OutlinedButton.icon(
                        onPressed: _isLoading ? null : _zeroDust,
                        icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                        label: const Text('Zero dust'),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 28),
              Text(
                'New Transaction',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                decoration: const InputDecoration(labelText: 'Transaction Type'),
                items: const [
                  DropdownMenuItem(
                    value: 'addToSort',
                    child: Text('Add to Sort (from baths)'),
                  ),
                  DropdownMenuItem(
                    value: 'plateBars',
                    child: Text('Plate Bars to Sell'),
                  ),
                  DropdownMenuItem(
                    value: 'removeFromSort',
                    child: Text('Remove from Sort (reuse + sell)'),
                  ),
                  DropdownMenuItem(
                    value: 'useReuse',
                    child: Text('Use from Reuse'),
                  ),
                ],
                onChanged: (v) => setState(() => _selectedType = v!),
              ),
              const SizedBox(height: 8),
              Text(
                _typeHelp(_selectedType),
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              if (_selectedType == 'removeFromSort') ...[
                TextField(
                  controller: _reuseKgController,
                  decoration: InputDecoration(
                    labelText: 'Reuse (kg)',
                    helperText:
                        'Available in sort: ${CopperService.roundKg(inv.sortKg).toStringAsFixed(1)} kg',
                  ),
                  keyboardType: _decimalKeyboard,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _sellKgController,
                  decoration: const InputDecoration(
                    labelText: 'Sell (kg)',
                    helperText: 'Goes to To Sell as nuggets',
                  ),
                  keyboardType: _decimalKeyboard,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Text(
                  'Total from sort: ${_sortTotal.toStringAsFixed(1)} kg',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _sortTotal >= 0 ? scheme.onSurface : Colors.red,
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _amountController,
                  decoration: InputDecoration(
                    labelText: 'Amount (kg)',
                    helperText: _selectedType == 'useReuse'
                        ? 'Available: ${CopperService.roundKg(inv.reuseKg).toStringAsFixed(1)} kg'
                        : null,
                    suffixIcon: (_selectedType == 'useReuse' && inv.reuseKg > 0)
                        ? TextButton(
                            onPressed: () => _fillAmount(inv.reuseKg),
                            child: const Text('All'),
                          )
                        : null,
                  ),
                  keyboardType: _decimalKeyboard,
                  onChanged: (_) => setState(() {}),
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
                      : const Text(
                          'Execute Transaction',
                          style: TextStyle(fontSize: 18),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryTab() {
    final isCopperAuth =
        isCopperAuthorized(ref.watch(currentEmployeeProvider).valueOrNull);

    return StreamBuilder<List<CopperTransaction>>(
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
              child: ListView.separated(
                itemCount: txs.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final tx = txs[index];
                  final titleBits = <String>[
                    tx.type.toUpperCase(),
                    '${tx.amountKg.toStringAsFixed(1)} kg',
                  ];
                  if (tx.wasteLoadNumber != null &&
                      tx.wasteLoadNumber!.isNotEmpty) {
                    titleBits.add(tx.wasteLoadNumber!);
                  }
                  return Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ListTile(
                      leading: Icon(_getIcon(tx.type), color: _getColor(tx.type)),
                      title: Text(titleBits.join(' • ')),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (tx.fromBucket != null || tx.toBucket != null)
                            Text('${tx.fromBucket ?? ''} → ${tx.toBucket ?? ''}'),
                          if (tx.rPerKg != null && isCopperAuth)
                            Text('R/kg: ${tx.rPerKg!.toStringAsFixed(2)}'),
                          if (tx.copperSubtype != null &&
                              tx.copperSubtype!.isNotEmpty)
                            Text('Subtype: ${tx.copperSubtype}'),
                          Text(
                            tx.comments,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      trailing: Text(
                        DateFormat('dd/MM HH:mm').format(tx.timestamp.toDate()),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final employee = ref.watch(currentEmployeeProvider).valueOrNull;
    if (!isCopperAuthorized(employee)) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Copper is limited to admins and Pre Press managers.\n'
              'You do not have access.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 15,
              ),
            ),
          ),
        ),
      );
    }

    final isPushedRoute = ModalRoute.of(context)?.canPop ?? false;

    return Scaffold(
      appBar: isPushedRoute
          ? AppBar(
              title: const Text(
                'Copper Management',
                style: TextStyle(color: Colors.black),
              ),
              backgroundColor: Colors.amber,
              elevation: 0,
            )
          : null,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isLargeScreen = constraints.maxWidth > 1200;
          if (isLargeScreen) {
            return Row(
              children: [
                Expanded(child: _buildTransactionTab()),
                Expanded(child: _buildHistoryTab()),
              ],
            );
          }
          return Column(
            children: [
              TabBar(
                controller: _tabController,
                isScrollable: false,
                tabs: const [
                  Tab(text: 'Make Transaction'),
                  Tab(text: 'History'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTransactionTab(),
                    _buildHistoryTab(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBucketCard(String title, double kg, Color color, IconData icon) {
    final display = CopperService.roundKg(kg);
    return Expanded(
      child: Card(
        color: color.withAlpha(26),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                '${display.toStringAsFixed(1)} kg',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (display / _bucketMaxKg).clamp(0.0, 1.0),
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
      case CopperTransaction.addToSort:
        return Icons.add_circle;
      case CopperTransaction.plateBars:
        return Icons.build_circle;
      case CopperTransaction.sort:
        return Icons.sort;
      case CopperTransaction.useReuse:
        return Icons.remove_circle;
      case CopperTransaction.recordSale:
      case CopperTransaction.recordSaleFromWaste:
        return Icons.attach_money;
      case CopperTransaction.prepareForCollection:
        return Icons.inventory_2_outlined;
      case CopperTransaction.adjust:
        return Icons.tune;
      case CopperTransaction.zeroDust:
        return Icons.cleaning_services_outlined;
      default:
        return Icons.help;
    }
  }

  Color _getColor(String type) {
    switch (type) {
      case CopperTransaction.addToSort:
        return Colors.blue;
      case CopperTransaction.plateBars:
        return Colors.purple;
      case CopperTransaction.sort:
        return Colors.green;
      case CopperTransaction.useReuse:
        return Colors.red;
      case CopperTransaction.recordSale:
      case CopperTransaction.recordSaleFromWaste:
        return Colors.amber;
      case CopperTransaction.prepareForCollection:
        return Colors.orange;
      case CopperTransaction.adjust:
      case CopperTransaction.zeroDust:
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }
}
