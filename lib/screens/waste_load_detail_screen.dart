import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../models/waste_load.dart';
import '../models/waste_item.dart';
import '../models/waste_type.dart';
import '../utils/formatters.dart';
import '../utils/role.dart' as role_utils;
import '../main.dart' show currentEmployee;
import '../theme/app_theme.dart';
import '../utils/waste_stock_mapping.dart';
import '../utils/waste_type_routing.dart';
import '../widgets/waste_app_bar.dart';
import 'waste_signature_screen.dart';
import '../services/waste_service.dart';

import '../widgets/waste_add_item_sheet.dart';
import '../widgets/waste_stock_link_sheet.dart';

/// View / edit a single Waste Load.
/// Supports item deletion (role-gated), adding items to in-progress loads,
/// and driver-signature completion. Weighbridge and cost review are handled in CTP Pulse.
class WasteLoadDetailScreen extends ConsumerStatefulWidget {
  final WasteLoad load;

  const WasteLoadDetailScreen({super.key, required this.load});

  @override
  ConsumerState<WasteLoadDetailScreen> createState() => _WasteLoadDetailScreenState();
}

class _WasteLoadDetailScreenState extends ConsumerState<WasteLoadDetailScreen> {
  final WasteService _wasteService = WasteService();
  late WasteLoad _currentLoad;
  final List<String> _finishLoadPhotoPaths = [];
  bool _addingFinishPhoto = false;
  bool _wasteItemsExpanded = false;
  bool _isAdmin = false;
  bool _isManager = false;
  bool _photosRequired = false;
  bool _isSaving = false;
  List<WasteType> _wasteTypes = [];
  StreamSubscription<WasteLoad?>? _loadSubscription;

  @override
  void initState() {
    super.initState();
    _currentLoad = widget.load;
    _isAdmin = role_utils.isWasteAdmin(currentEmployee);
    _wasteService.processOfflineWasteQueue();
    _wasteService.getWasteSettings().then((s) {
      if (mounted) {
        setState(() {
          _isManager = role_utils.isSecurityManager(currentEmployee, s);
          _photosRequired = s.photosRequired;
        });
      }
    });
    _wasteService.watchWasteTypes().first.then((types) {
      if (mounted) setState(() => _wasteTypes = types);
    }).catchError((_) {});
    final loadId = _currentLoad.id;
    if (loadId != null) {
      _loadSubscription = _wasteService.watchLoad(loadId).listen((load) {
        if (load != null && mounted) {
          setState(() => _currentLoad = load);
        }
      });
    }
  }

  @override
  void dispose() {
    _loadSubscription?.cancel();
    super.dispose();
  }

  bool get _isCompleted => _currentLoad.status == WasteLoadStatus.completed;
  bool get _canManageItems => _isAdmin || _isManager;
  bool get _usesPaperStock =>
      loadUsesPaperStock(_currentLoad.mainWasteType, _wasteTypes);

  Set<String>? get _stockSubtypeFilter {
    if (_currentLoad.mainWasteType == kPaperWasteStockParent) return null;
    if (_usesPaperStock) return {_currentLoad.mainWasteType};
    return null;
  }
  bool get _isScheduled => _currentLoad.status == WasteLoadStatus.scheduled;

  /// Can a user delete a specific item?
  bool _canDelete(WasteItem item) {
    if (_isCompleted) return _isAdmin; // only admin on completed loads
    return _canManageItems;
  }

  Widget _buildPulseHandoffBanner(WasteLoadStatus status) {
    final isWeighbridge = status == WasteLoadStatus.pendingWeighbridge;
    final bg = isWeighbridge ? Colors.amber.shade50 : Colors.purple.shade50;
    final border = isWeighbridge ? Colors.amber.shade600 : Colors.purple.shade400;
    final iconColor = isWeighbridge ? Colors.amber.shade800 : Colors.purple.shade700;
    final titleColor = isWeighbridge ? Colors.amber.shade900 : Colors.purple.shade900;
    final bodyColor = isWeighbridge ? Colors.amber.shade800 : Colors.purple.shade800;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isWeighbridge ? Icons.scale : Icons.rate_review,
            color: iconColor,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isWeighbridge
                      ? 'Awaiting weighbridge in CTP Pulse'
                      : 'Awaiting cost review in CTP Pulse',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isWeighbridge
                      ? 'Off-site weighbridge entry and deviation checks are completed in CTP Pulse. This load will update here once processed.'
                      : 'Admin cost review and completion are handled in CTP Pulse. This load will update here once approved.',
                  style: TextStyle(fontSize: 12, color: bodyColor),
                ),
                if (!isWeighbridge && _currentLoad.randValueExVat != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Suggested value: R ${_currentLoad.randValueExVat!.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: bodyColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _removePhoto(WasteItem item, String photoUrl) async {
    if (item.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Photo?'),
        content: Text(
          'Remove this photo from "${item.subtype}"? '
          'The image will be deleted from storage.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _wasteService.removePhotoFromWasteItem(
        itemId: item.id!,
        photoUrl: photoUrl,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo removed'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove photo: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteItem(WasteItem item) async {
    final isCompleted = _isCompleted;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Item?'),
        content: Text(
          isCompleted
              ? 'This load is completed. Deleting "${item.subtype}" is permanent and cannot be undone.'
              : item.isQuantityOnly
                  ? 'Remove "${item.subtype}" (qty ${item.quantity ?? 0}) from this load?'
                  : 'Remove "${item.subtype}" (${item.weightKg.toStringAsFixed(1)} kg) from this load?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || item.id == null) return;

    try {
      await _wasteService.deleteWasteItem(item.id!, sourceStockId: item.sourceStockId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item removed'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _linkStockToLoad() async {
    if (_currentLoad.id == null) return;
    final picked = await WasteStockLinkSheet.show(
      context,
      wasteType: kPaperWasteStockParent,
      subtypeFilter: _stockSubtypeFilter,
      initialSelectedIds: _currentLoad.selectedStockIds,
      title: _isScheduled ? 'Link stock for collection' : 'Select on-site stock',
      subtitle: _isScheduled
          ? 'The guard will see these items when they start collection.'
          : 'Choose stock items to add to this load.',
    );
    if (picked == null || !mounted) return;

    setState(() => _isSaving = true);
    try {
      if (_isScheduled) {
        await _wasteService.updateLoadSelectedStock(_currentLoad.id!, picked);
        setState(() {
          _currentLoad = _currentLoad.copyWith(selectedStockIds: picked);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                picked.isEmpty
                    ? 'Stock links cleared'
                    : '${picked.length} stock item${picked.length == 1 ? '' : 's'} linked',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        final added = await _wasteService.addStockItemsToLoad(
          loadId: _currentLoad.id!,
          stockIds: picked,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                added > 0
                    ? '$added stock item${added == 1 ? '' : 's'} added to load'
                    : 'No on-site stock items were added',
              ),
              backgroundColor: added > 0 ? Colors.green : Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Set<String> get _quantityOnlyTypeNames =>
      _wasteTypes.where((t) => t.isQuantityOnly).map((t) => t.mainType).toSet();

  Set<String> get _noSiteWeightTypeNames =>
      _wasteTypes.where((t) => t.noSiteWeight).map((t) => t.mainType).toSet();

  Map<String, String> get _quantityLabelByType => {
        for (final t in _wasteTypes)
          if (t.isQuantityOnly || t.noSiteWeight)
            t.mainType: t.quantityLabelFor('default'),
      };

  Future<void> _addItem() async {
    final typeNames = _wasteTypes.map((t) => t.mainType).toList();
    final result = await showModalBottomSheet<WasteAddItemSheetResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: WasteAddItemSheet(
            types: typeNames,
            defaultType: _currentLoad.mainWasteType,
            title: 'Add Item to Load',
            quantityOnlyTypeNames: _quantityOnlyTypeNames,
            noSiteWeightTypeNames: _noSiteWeightTypeNames,
            quantityLabelByType: _quantityLabelByType,
            photosRequired: _photosRequired,
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final addResult = await _wasteService.addItemToExistingLoad(
        loadId: _currentLoad.id!,
        subtype: result.subtype,
        weightKg: result.weightKg,
        quantity: result.quantity,
        notes: result.notes,
        localPhotoPaths: result.localPhotoPaths,
        isQuantityOnly: result.isQuantityOnly,
        isNoSiteWeight: result.isNoSiteWeight,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              addResult.queuedOffline
                  ? 'Item saved offline — will sync when connection returns'
                  : 'Item added',
            ),
            backgroundColor: addResult.queuedOffline ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add item: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _addFinishPhoto(ImageSource source) async {
    setState(() => _addingFinishPhoto = true);
    try {
      final path = await _wasteService.pickAndCompressPhotoFromSource(source);
      if (path != null && mounted) setState(() => _finishLoadPhotoPaths.add(path));
    } finally {
      if (mounted) setState(() => _addingFinishPhoto = false);
    }
  }

  bool get _canShare => _isCompleted || _isAdmin || _isManager;

  Future<void> _shareLoadSummary() async {
    final load = _currentLoad;
    List<WasteItem> items = [];
    try {
      items = await _wasteService
          .watchItemsForLoad(load.id!)
          .first
          .timeout(const Duration(seconds: 8), onTimeout: () => []);
    } catch (_) {}

    final pdf = pw.Document();
    final wasteGreen = PdfColor.fromHex('#2e7d32');
    const borderColor = PdfColor.fromInt(0xFF9E9E9E);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) {
          final double calcTotal = items.fold(
            0.0,
            (acc, i) => acc + i.weightKg * (i.ratePerKg ?? 0),
          );
          final approvedCost = load.randValueExVat;
          final calculatedCost = load.calculatedCost ?? calcTotal;

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ── Header ──
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: pw.BoxDecoration(
                  color: wasteGreen,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'CTP — Waste Load Summary',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    pw.Text(
                      load.loadNumber.isNotEmpty ? load.loadNumber : '—',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // ── Load info table ──
              _pdfInfoTable([
                ['Date', _formatPdfDate(load.dateTime)],
                ['Waste Type', load.mainWasteType],
                ['Contractor', load.contractorName?.isNotEmpty == true ? load.contractorName! : load.contractorId],
                ['Driver', load.driverName.isNotEmpty ? load.driverName : '—'],
                ['Vehicle', load.vehicleReg.isNotEmpty ? load.vehicleReg : '—'],
              ], borderColor: borderColor),
              pw.SizedBox(height: 16),

              // ── Items collected ──
              if (items.isNotEmpty) ...[
                pw.Text(
                  'Items Collected',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                ),
                pw.SizedBox(height: 6),
                _pdfItemsTable(items, borderColor: borderColor),
                pw.SizedBox(height: 16),
              ],

              // ── Weighbridge ──
              if (load.actualWeighbridgeWeightKg != null) ...[
                pw.Text(
                  'Weighbridge',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                ),
                pw.SizedBox(height: 6),
                _pdfInfoTable([
                  if (load.weighbridgeNumber?.isNotEmpty == true)
                    ['Ticket #', load.weighbridgeNumber!],
                  ['Actual weight', '${load.actualWeighbridgeWeightKg!.toStringAsFixed(0)} kg'],
                  if (load.recordedWeightKg > 0) ...[
                    ['Recorded weight', '${load.recordedWeightKg.toStringAsFixed(0)} kg'],
                    [
                      'Deviation',
                      '${(load.actualWeighbridgeWeightKg! - load.recordedWeightKg) >= 0 ? '+' : ''}'
                      '${(load.actualWeighbridgeWeightKg! - load.recordedWeightKg).toStringAsFixed(0)} kg',
                    ],
                  ],
                  if (load.weighbridgeTicketWaived)
                    ['Note', 'Ticket waived by ${load.weighbridgeTicketWaivedByName ?? load.weighbridgeTicketWaivedBy ?? 'admin'}'],
                ], borderColor: borderColor),
                pw.SizedBox(height: 16),
              ],

              // ── Cost ──
              if (approvedCost != null || calculatedCost > 0) ...[
                pw.Text(
                  'Cost (ex VAT)',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                ),
                pw.SizedBox(height: 6),
                _pdfInfoTable([
                  if (calculatedCost > 0)
                    ['Calculated', 'R ${calculatedCost.toStringAsFixed(2)}'],
                  if (approvedCost != null)
                    ['Approved', 'R ${approvedCost.toStringAsFixed(2)}'],
                  if (load.costReviewedBy?.isNotEmpty == true)
                    ['Approved by', load.costReviewedBy!],
                  if (load.costReviewedAt != null)
                    ['Approved on', _formatPdfDate(load.costReviewedAt!)],
                ], borderColor: borderColor),
              ],

              pw.Spacer(),
              pw.Divider(color: borderColor),
              pw.Text(
                'Generated ${_formatPdfDate(DateTime.now())} • CTP Job Cards',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    final tmpDir = await getTemporaryDirectory();
    final label = load.loadNumber.isNotEmpty
        ? load.loadNumber.replaceAll(RegExp(r'[^A-Za-z0-9\-]'), '_')
        : 'waste_load';
    final file = File('${tmpDir.path}/$label.pdf');
    await file.writeAsBytes(bytes);

    if (!mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Waste Load Summary — ${load.loadNumber.isNotEmpty ? load.loadNumber : load.mainWasteType}',
      ),
    );
  }

  String _formatPdfDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  static pw.Widget _pdfInfoTable(
    List<List<String>> rows, {
    required PdfColor borderColor,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: borderColor, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(1.4),
        1: const pw.FlexColumnWidth(2.6),
      },
      children: rows.map((row) {
        return pw.TableRow(children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: pw.Text(
              row[0],
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: pw.Text(
              row.length > 1 ? row[1] : '—',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
        ]);
      }).toList(),
    );
  }

  static pw.Widget _pdfItemsTable(
    List<WasteItem> items, {
    required PdfColor borderColor,
  }) {
    final hasQtyOnly = items.any((i) => i.isQuantityOnly);
    final double total = items.fold(0.0, (s, i) => s + (i.lineValue ?? 0));

    final headers = hasQtyOnly
        ? ['Subtype', 'Qty / Weight', 'R/unit or /kg', 'Value']
        : ['Subtype', 'Weight', 'R/kg', 'Value'];

    return pw.Table(
      border: pw.TableBorder.all(color: borderColor, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(2.5),
        1: const pw.FlexColumnWidth(1.5),
        2: const pw.FlexColumnWidth(1.5),
        3: const pw.FlexColumnWidth(1.5),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF5F5F5)),
          children: headers.map((h) {
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: pw.Text(
                h,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey700,
                ),
              ),
            );
          }).toList(),
        ),
        ...items.map((item) {
          final rate = item.ratePerKg;
          final value = item.lineValue;
          final measureCell = item.isQuantityOnly
              ? 'Qty ${item.quantity ?? 0}'
              : '${item.weightKg.toStringAsFixed(0)} kg';
          final rateCell = item.isQuantityOnly
              ? (rate != null ? 'R ${rate.toStringAsFixed(2)}/unit' : '—')
              : (rate != null ? 'R ${rate.toStringAsFixed(2)}' : '—');
          return pw.TableRow(children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: pw.Text(item.subtype, style: const pw.TextStyle(fontSize: 9)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: pw.Text(measureCell, style: const pw.TextStyle(fontSize: 9)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: pw.Text(rateCell, style: const pw.TextStyle(fontSize: 9)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: pw.Text(
                value != null ? 'R ${value.toStringAsFixed(2)}' : '—',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          ]);
        }),
        if (total > 0)
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF5F5F5)),
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: pw.Text(
                  'Total',
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(),
              pw.SizedBox(),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: pw.Text(
                  'R ${total.toStringAsFixed(2)}',
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                ),
              ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(_currentLoad.status);
    final recorded = _currentLoad.recordedWeightKg;
    final actual = _currentLoad.actualWeighbridgeWeightKg;

    return Scaffold(
      appBar: WasteAppBar(
        title: _currentLoad.loadNumber.isNotEmpty ? _currentLoad.loadNumber : 'Load Detail',
        isOnSite: currentEmployee?.isOnSite,
        actions: _canShare
            ? [
                IconButton(
                  icon: const Icon(Icons.share),
                  tooltip: 'Share load summary',
                  onPressed: _shareLoadSummary,
                ),
              ]
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          if (_currentLoad.status == WasteLoadStatus.pendingWeighbridge ||
              _currentLoad.status == WasteLoadStatus.pendingCostReview)
            _buildPulseHandoffBanner(_currentLoad.status),

          // ── Completed lock banner ─────────────────────────
          if (_isCompleted)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade400),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, color: Colors.green.shade700, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isAdmin
                          ? 'Load is completed and locked. Admin can still delete items.'
                          : 'Load is completed and locked. Contact admin to make changes.',
                      style: TextStyle(fontSize: 12, color: Colors.green.shade800),
                    ),
                  ),
                ],
              ),
            ),

          // ── Status stepper ────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _WasteStatusStepper(status: _currentLoad.status),
          ),

          // ── Status banner ─────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(_statusIcon(_currentLoad.status), color: statusColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_currentLoad.mainWasteType,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      Text(_currentLoad.status.displayLabel,
                          style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Info card ─────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow(Icons.person, 'Driver',
                      _currentLoad.driverName.isNotEmpty ? _currentLoad.driverName : '—'),
                  const Divider(height: 16),
                  _infoRow(Icons.local_shipping, 'Vehicle',
                      _currentLoad.vehicleReg.isNotEmpty ? _currentLoad.vehicleReg : '—'),
                  const Divider(height: 16),
                  _infoRow(Icons.business, 'Contractor',
                      (_currentLoad.contractorName?.isNotEmpty == true)
                          ? _currentLoad.contractorName!
                          : (_currentLoad.contractorId.isNotEmpty ? _currentLoad.contractorId : '—')),
                  const Divider(height: 16),
                  _infoRow(Icons.calendar_today, 'Date', formatSADate(_currentLoad.dateTime)),
                  if (_currentLoad.collectedBy != null) ...[
                    const Divider(height: 16),
                    _infoRow(Icons.badge, 'Collected by',
                        _currentLoad.collectedByName?.isNotEmpty == true
                            ? _currentLoad.collectedByName!
                            : _currentLoad.collectedBy!),
                  ],
                ],
              ),
            ),
          ),

          if (_usesPaperStock && _canManageItems && !_isCompleted) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('On-Site Stock',
                        style:
                            TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(
                      _isScheduled
                          ? '${_currentLoad.selectedStockIds.length} item${_currentLoad.selectedStockIds.length == 1 ? '' : 's'} linked for guard collection.'
                          : 'Add recorded Paper Waste stock directly to this load.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _isSaving ? null : _linkStockToLoad,
                        icon: const Icon(Icons.layers_outlined, size: 18),
                        label: Text(_isScheduled
                            ? 'Manage linked stock'
                            : 'Add from on-site stock'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // ── Items section ─────────────────────────────────
          const SizedBox(height: 12),
          if (_currentLoad.id != null)
            StreamBuilder<List<WasteItem>>(
              stream: _wasteService.watchItemsForLoad(_currentLoad.id!),
              builder: (context, snap) {
                final items = snap.data ?? [];
                if (snap.connectionState == ConnectionState.waiting && items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }

                final canAdd = _canManageItems && !_isCompleted;

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: items.isEmpty
                              ? null
                              : () => setState(
                                    () => _wasteItemsExpanded = !_wasteItemsExpanded,
                                  ),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Waste Items (${items.length})',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                if (canAdd)
                                  TextButton.icon(
                                    onPressed: _isSaving ? null : _addItem,
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('Add'),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    ),
                                  ),
                                if (items.isNotEmpty)
                                  Icon(
                                    _wasteItemsExpanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No items recorded.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          )
                        else if (!_wasteItemsExpanded)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 4),
                            child: Text(
                              'Tap header to show ${items.length} item${items.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).appColors.textMuted,
                              ),
                            ),
                          )
                        else ...[
                          const SizedBox(height: 8),
                          ...items.map((item) => _ItemRow(
                            item: item,
                            canDelete: _canDelete(item),
                            canRemovePhotos: _canDelete(item),
                            onDelete: () => _deleteItem(item),
                            onRemovePhoto: (url) => _removePhoto(item, url),
                          )),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),

          // ── Weight card ───────────────────────────────────
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Weight', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _weightBox('Recorded\n(items)', recorded > 0 ? formatSAWeight(recorded) : '—', Colors.blue)),
                      const SizedBox(width: 12),
                      Expanded(child: _weightBox('Weighbridge', actual != null ? formatSAWeight(actual) : '—', actual != null ? Colors.green : Colors.grey)),
                    ],
                  ),
                  if (recorded > 0 && actual != null) ...[
                    const SizedBox(height: 10),
                    Builder(builder: (ctx) {
                      final diff = actual - recorded;
                      final pct = (diff / recorded * 100);
                      final isOk = diff.abs() <= recorded * 0.05 && diff.abs() <= 50;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isOk ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isOk ? Colors.green.shade400 : Colors.red.shade400),
                        ),
                        child: Row(
                          children: [
                            Icon(isOk ? Icons.check_circle : Icons.warning_amber,
                                color: isOk ? Colors.green : Colors.red, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Variance: ${diff >= 0 ? '+' : ''}${formatSAWeight(diff)}  (${pct.abs().toStringAsFixed(1)}%)',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isOk ? Colors.green.shade800 : Colors.red.shade800,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── Finish loading (draft on-the-spot loads) ───────
          if (_currentLoad.status == WasteLoadStatus.draft) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Finish Loading', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 6),
                    Text(
                      'Truck is loaded — capture the driver signature before it leaves. Truck photos are optional.',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).appColors.textMuted),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ..._finishLoadPhotoPaths.map((path) => ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(File(path), width: 72, height: 72, fit: BoxFit.cover),
                        )),
                        if (!_addingFinishPhoto) ...[
                          OutlinedButton.icon(
                            onPressed: () => _addFinishPhoto(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt, size: 18),
                            label: const Text('Truck photo (optional)'),
                          ),
                        ] else
                          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _finishLoading,
                        icon: const Icon(Icons.local_shipping),
                        label: const Text('Finish Loading & Capture Signature'),
                        style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          if (_isAdmin) ...[
            const SizedBox(height: 16),
            Text('Admin: soft-delete (load level) available in a future version.',
                style: TextStyle(fontSize: 12, color: Theme.of(context).appColors.textMuted)),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Draft load: truck photos + signature → pending cost review (qty-only) or
  /// pending weighbridge (weight-based, off-site document to follow).
  Future<void> _finishLoading() async {
    final signatureBytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
        builder: (_) => WasteSignatureScreen(loadNumber: _currentLoad.loadNumber),
      ),
    );
    if (signatureBytes == null || !mounted) return;

    setState(() => _isSaving = true);
    final skipWeighbridge = mainTypeSkipsWeighbridge(
      _currentLoad.mainWasteType,
      _wasteTypes,
    );
    String? signatureTempPath;
    try {
      final tmp = await Directory.systemTemp.createTemp('waste_sig');
      final file = File('${tmp.path}/sig_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(signatureBytes);
      signatureTempPath = file.path;

      final result = await _wasteService.finishLoading(
        loadId: _currentLoad.id!,
        loadPhotoPaths: _finishLoadPhotoPaths,
        signatureLocalPath: signatureTempPath,
        finishedBy: currentEmployee?.clockNo ?? '',
        finishedByName: currentEmployee?.name,
        isQuantityOnly: skipWeighbridge,
      );

      final nextStatus = skipWeighbridge
          ? WasteLoadStatus.pendingCostReview
          : WasteLoadStatus.pendingWeighbridge;
      setState(() {
        _currentLoad = _currentLoad.copyWith(
          status: nextStatus,
          pendingWeighbridgeAt: skipWeighbridge ? null : DateTime.now(),
          collectedBy: currentEmployee?.clockNo,
          collectedByName: currentEmployee?.name,
        );
        _finishLoadPhotoPaths.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.queuedOffline
                  ? 'Finish loading saved offline — will sync when connection returns'
                  : skipWeighbridge
                      ? 'Loading finished — complete cost review in CTP Pulse'
                      : 'Loading finished — complete weighbridge entry in CTP Pulse',
            ),
            backgroundColor: result.queuedOffline ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      final refreshed = _currentLoad.id != null
          ? await _wasteService.getLoad(_currentLoad.id!)
          : null;
      if (!mounted) return;
      if (refreshed != null &&
          (refreshed.status == WasteLoadStatus.pendingWeighbridge ||
           refreshed.status == WasteLoadStatus.pendingCostReview)) {
        setState(() {
          _currentLoad = refreshed;
          _finishLoadPhotoPaths.clear();
        });
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              refreshed.status == WasteLoadStatus.pendingCostReview
                  ? 'Loading already finished — complete cost review in CTP Pulse.'
                  : 'Loading already finished — complete weighbridge entry in CTP Pulse.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Finish failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text('$label  ', style: TextStyle(color: Theme.of(context).appColors.textMuted, fontSize: 13)),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
      ],
    );
  }

  Widget _weightBox(String label, String value, Color accent) {
    final theme = Theme.of(context);
    final isEmpty = value == '—';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isEmpty
            ? theme.colorScheme.surfaceContainerHighest
            : accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isEmpty
              ? theme.dividerColor
              : accent.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: theme.appColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: isEmpty
                  ? theme.colorScheme.onSurfaceVariant
                  : accent,
            ),
          ),
        ],
      ),
    );
  }

  IconData _statusIcon(WasteLoadStatus s) {
    switch (s) {
      case WasteLoadStatus.completed:          return Icons.check_circle;
      case WasteLoadStatus.scheduled:          return Icons.event_available;
      case WasteLoadStatus.pendingWeighbridge: return Icons.scale;
      case WasteLoadStatus.pendingCostReview: return Icons.rate_review;
      case WasteLoadStatus.cancelled:          return Icons.cancel;
      default:                                 return Icons.hourglass_bottom;
    }
  }

  Color _statusColor(WasteLoadStatus s) {
    switch (s) {
      case WasteLoadStatus.completed:          return Colors.green;
      case WasteLoadStatus.scheduled:          return Colors.blue;
      case WasteLoadStatus.pendingWeighbridge: return Colors.amber.shade700;
      case WasteLoadStatus.pendingCostReview: return Colors.purple;
      case WasteLoadStatus.cancelled:          return Theme.of(context).colorScheme.onSurfaceVariant;
      default:                                 return Colors.orange;
    }
  }
}

// ---------------------------------------------------------------------------
// Per-item row with inline delete button
// ---------------------------------------------------------------------------

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.canDelete,
    required this.canRemovePhotos,
    required this.onDelete,
    required this.onRemovePhoto,
  });

  final WasteItem item;
  final bool canDelete;
  final bool canRemovePhotos;
  final VoidCallback onDelete;
  final void Function(String photoUrl) onRemovePhoto;

  @override
  Widget build(BuildContext context) {
    final remotePhotos = item.photos
        .where((p) => p.startsWith('http://') || p.startsWith('https://'))
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.delete_outline, size: 16, color: Theme.of(context).appColors.wasteGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(item.subtype,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                        if (item.sourceStockId != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Theme.of(context).appColors.wasteGreenSurface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Theme.of(context).appColors.wasteGreen),
                            ),
                            child: Text('Stock',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context).appColors.wasteGreen,
                                    fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                    Text(
                      item.isQuantityOnly
                          ? 'Qty ${item.quantity ?? 0}'
                              '${item.photos.isNotEmpty ? '  •  ${item.photos.length} photo(s)' : ''}'
                          : '${item.weightKg.toStringAsFixed(1)} kg'
                              '${item.quantity != null ? '  •  Qty ${item.quantity}' : ''}'
                              '${item.photos.isNotEmpty ? '  •  ${item.photos.length} photo(s)' : ''}',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).appColors.textMuted),
                    ),
                  ],
                ),
              ),
              if (canDelete)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  tooltip: 'Delete item',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: onDelete,
                ),
            ],
          ),
          if (remotePhotos.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: remotePhotos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final url = remotePhotos[i];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: url,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            width: 72,
                            height: 72,
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            width: 72,
                            height: 72,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.broken_image, size: 20),
                          ),
                        ),
                      ),
                      if (canRemovePhotos)
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => onRemovePhoto(url),
                            child: const CircleAvatar(
                              radius: 10,
                              backgroundColor: Colors.red,
                              child: Icon(Icons.close, size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status stepper
// ---------------------------------------------------------------------------

class _WasteStatusStepper extends StatelessWidget {
  const _WasteStatusStepper({required this.status});
  final WasteLoadStatus status;

  @override
  Widget build(BuildContext context) {
    final steps = status == WasteLoadStatus.scheduled
        ? ['Scheduled', 'Loading', 'Weighbridge', 'Review', 'Done']
        : ['Created', 'Loading', 'Weighbridge', 'Review', 'Done'];
    final currentIdx = switch (status) {
      WasteLoadStatus.scheduled          => 0,
      WasteLoadStatus.draft              => 1,
      WasteLoadStatus.pendingWeighbridge => 2,
      WasteLoadStatus.pendingCostReview  => 3,
      WasteLoadStatus.completed          => 4,
      WasteLoadStatus.cancelled          => -1,
    };
    if (status == WasteLoadStatus.cancelled) {
      final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.cancel, size: 16, color: mutedColor),
            const SizedBox(width: 8),
            Text('Cancelled', style: TextStyle(color: mutedColor, fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }
    return Row(
      children: List.generate(steps.length, (i) {
        final done = i < currentIdx;
        final active = i == currentIdx;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done ? Theme.of(context).appColors.wasteGreen
                            : active ? Colors.orange
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        border: active ? Border.all(color: Colors.orange, width: 2) : null,
                      ),
                      child: Icon(
                        done ? Icons.check : Icons.circle,
                        size: done ? 16 : 8,
                        color: done ? Colors.white : active ? Colors.orange : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      steps[i],
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: active ? FontWeight.bold : FontWeight.normal,
                        color: active ? Colors.orange
                            : done ? Theme.of(context).appColors.wasteGreen
                            : Theme.of(context).appColors.textMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              if (i < steps.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 18),
                    color: done ? Theme.of(context).appColors.wasteGreen : Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}
