import 'package:flutter/material.dart';
import '../utils/persona_audit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ink_ibc.dart';
import '../models/ink_stock_item.dart';
import '../providers/ink_provider.dart';
import '../services/ink_barcode_parser.dart';
import 'ink_barcode_scan_screen.dart';
import 'ink_ibc_consume_confirm_screen.dart';
import '../utils/screen_insets.dart';
import '../utils/user_facing_error.dart';

/// Consume IBC — scan-first flow with colour tabs as fallback. Confirm on a
/// full screen (wash + time). Tab labels show how many IBCs were consumed this
/// count period per colour, e.g. Yellow (3).
class InkIbcTransferScreen extends ConsumerStatefulWidget {
  const InkIbcTransferScreen({super.key});

  @override
  ConsumerState<InkIbcTransferScreen> createState() => _State();
}

class _State extends ConsumerState<InkIbcTransferScreen>
    with SingleTickerProviderStateMixin {
  static final _qty = NumberFormat('#,##0.##');

  late final TabController _tab;
  bool _showPickList = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: kInkColourCodes.length, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  String? _tolulItemCode(List<InkStockItem> items) {
    for (final i in items) {
      if (i.itemClass == InkItemClass.solvent) return i.itemCode;
    }
    return null;
  }

  String _colourLabel(String itemCode) {
    final idx = kInkColourCodes.indexOf(itemCode);
    if (idx >= 0) return kInkColourLabels[idx];
    return itemCode.isEmpty
        ? 'Unknown'
        : itemCode[0].toUpperCase() + itemCode.substring(1);
  }

  Future<void> _openConfirm(InkIbc ibc) async {
    final items = ref.read(inkStockItemsProvider).valueOrNull ?? [];
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => InkIbcConsumeConfirmScreen(
          ibc: ibc,
          tolulItemCode: _tolulItemCode(items),
          colourLabel: _colourLabel(ibc.itemCode),
        ),
      ),
    );
    if (ok == true && mounted) {
      setState(() => _showPickList = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('IBC consumed; wash recorded.')),
      );
    }
  }

  Future<void> _scan() async {
    if (!guardPersonaSubmit(context)) return;
    final res = await Navigator.push<IbcScanResult>(
      context,
      MaterialPageRoute(builder: (_) => const InkBarcodeScanScreen()),
    );
    if (res == null || res.ibcNumber == null || !mounted) return;
    final number = res.ibcNumber!;
    final received = ref.read(inkReceivedIbcsProvider).valueOrNull ?? [];
    InkIbc? match;
    for (final i in received) {
      if (i.ibcNumber == number) {
        match = i;
        break;
      }
    }
    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('IBC "$number" is not awaiting consumption.')));
      return;
    }
    await _openConfirm(match);
  }

  void _onPickFromList(InkIbc ibc) => _openConfirm(ibc);

  @override
  Widget build(BuildContext context) {
    final ibcsAsync = ref.watch(inkReceivedIbcsProvider);
    final consumedCounts = ref.watch(inkIbcsConsumedCountByColourProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Consume IBC'),
        leading: _showPickList
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to scan',
                onPressed: () => setState(() => _showPickList = false),
              )
            : null,
        bottom: _showPickList
            ? TabBar(
                controller: _tab,
                isScrollable: true,
                labelColor: Colors.black,
                unselectedLabelColor: Colors.black54,
                indicatorColor: Colors.black,
                tabs: [
                  for (var i = 0; i < kInkColourLabels.length; i++)
                    Tab(
                      text: _tabLabel(
                        kInkColourLabels[i],
                        kInkColourCodes[i],
                        consumedCounts,
                      ),
                    ),
                ],
              )
            : null,
      ),
      body: _showPickList
          ? ibcsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorBody(
                message: userFacingError(
                  e,
                  loadFallback:
                      'Could not load IBCs. Check your connection and tap Retry.',
                ),
                onRetry: () => ref.invalidate(inkReceivedIbcsProvider),
              ),
              data: (all) => TabBarView(
                controller: _tab,
                children: [
                  for (final c in kInkColourCodes)
                    _IbcPickList(
                      ibcs: all.where((i) => i.itemCode == c).toList()
                        ..sort((a, b) => a.ibcNumber.compareTo(b.ibcNumber)),
                      onTap: _onPickFromList,
                      qty: _qty,
                      emptyLabel:
                          'No ${c[0].toUpperCase()}${c.substring(1)} IBCs awaiting consumption.',
                    ),
                ],
              ),
            )
          : _ScanLanding(
              onScan: _scan,
              onPickFromList: () => setState(() => _showPickList = true),
              awaitingCount: ibcsAsync.valueOrNull?.length,
              scheme: scheme,
            ),
    );
  }

  static String _tabLabel(
    String label,
    String code,
    Map<String, int> consumedCounts,
  ) {
    final n = consumedCounts[code] ?? 0;
    return n > 0 ? '$label ($n)' : label;
  }
}

// ── Scan-first landing ───────────────────────────────────────────────────────

class _ScanLanding extends StatelessWidget {
  const _ScanLanding({
    required this.onScan,
    required this.onPickFromList,
    required this.awaitingCount,
    required this.scheme,
  });

  final VoidCallback onScan;
  final VoidCallback onPickFromList;
  final int? awaitingCount;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        32,
        24,
        ScreenInsets.scrollBottomFullScreen(context),
      ),
      child: Column(
        children: [
          const Spacer(),
          Icon(Icons.qr_code_scanner, size: 88, color: scheme.primary),
          const SizedBox(height: 24),
          Text(
            'Scan the IBC barcode',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Point the camera at the label on the IBC you are emptying into the tank.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
          if (awaitingCount != null) ...[
            const SizedBox(height: 12),
            Text(
              '$awaitingCount IBC${awaitingCount == 1 ? '' : 's'} awaiting consumption',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: onScan,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan IBC'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onPickFromList,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
            child: const Text('Pick from list instead'),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Searchable IBC list for one colour tab ─────────────────────────────────────

class _IbcPickList extends StatefulWidget {
  const _IbcPickList({
    required this.ibcs,
    required this.onTap,
    required this.qty,
    required this.emptyLabel,
  });

  final List<InkIbc> ibcs;
  final void Function(InkIbc) onTap;
  final NumberFormat qty;
  final String emptyLabel;

  @override
  State<_IbcPickList> createState() => _IbcPickListState();
}

class _IbcPickListState extends State<_IbcPickList>
    with AutomaticKeepAliveClientMixin {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final filtered = widget.ibcs
        .where((i) =>
            _query.isEmpty ||
            i.ibcNumber.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: InputDecoration(
              hintText: 'Search IBC number…',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24)),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      })
                  : null,
            ),
          ),
        ),
        if (widget.ibcs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${filtered.length} awaiting',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _query.isNotEmpty
                          ? 'No IBCs match "$_query".'
                          : widget.emptyLabel,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 52),
                  itemBuilder: (_, idx) {
                    final ibc = filtered[idx];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 2),
                      leading: Icon(Icons.propane_tank_outlined,
                          color: scheme.primary),
                      title: Text(
                        ibc.ibcNumber,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        [
                          '${widget.qty.format(ibc.kg)} kg',
                          if (ibc.chargeNumber != null)
                            'Charge ${ibc.chargeNumber}',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => widget.onTap(ibc),
                    );
                  },
                ),
        ),
      ],
    );
  }
}