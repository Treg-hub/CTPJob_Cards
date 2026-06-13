import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../constants/collections.dart';
import '../models/ink_settings.dart';
import '../models/ink_stock_item.dart';
import '../models/ink_supplier.dart';
import '../models/ink_transaction.dart';

/// All Ink Factory Firestore operations. Follows the FleetService/WasteService
/// singleton pattern.
///
/// OFFLINE: every write here is a plain Firestore doc write, so the SDK's
/// built-in offline persistence queues it on poor signal and replays it on
/// reconnect. The server trigger (`onInkTransactionWritten`) then assigns the
/// `INK-####`, recomputes balance/WAC by `effective_at`, and updates the
/// stock-item cache. Until a queued entry reaches the server the operator sees
/// a "pending #" and a provisional balance — by design.
class InkService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  // ---------------------------------------------------------------------------
  // SETTINGS
  // ---------------------------------------------------------------------------

  Stream<InkSettings> watchSettings() => _db
      .collection(Collections.inkSettings)
      .doc('config')
      .snapshots()
      .map((s) => s.exists ? InkSettings.fromFirestore(s) : InkSettings.defaults);

  Future<void> saveSettings(InkSettings settings) => _db
      .collection(Collections.inkSettings)
      .doc('config')
      .set(settings.toFirestore(), SetOptions(merge: true));

  // ---------------------------------------------------------------------------
  // STOCK ITEMS (cache of the ledger — read-only on the client)
  // ---------------------------------------------------------------------------

  Stream<List<InkStockItem>> watchStockItems({bool activeOnly = true}) => _db
      .collection(Collections.inkStockItems)
      .snapshots()
      .map((s) {
        final items = s.docs.map(InkStockItem.fromFirestore).toList();
        final filtered = activeOnly ? items.where((i) => i.active).toList() : items;
        filtered.sort((a, b) => a.displayName.compareTo(b.displayName));
        return filtered;
      });

  Stream<InkStockItem?> watchStockItem(String itemCode) => _db
      .collection(Collections.inkStockItems)
      .doc(itemCode)
      .snapshots()
      .map((s) => s.exists ? InkStockItem.fromFirestore(s) : null);

  // ---------------------------------------------------------------------------
  // LEDGER
  // ---------------------------------------------------------------------------

  /// Records a transaction. The [InkTransaction.idempotencyKey] is used as the
  /// document id so an offline replay / retry never duplicates the entry.
  /// Server-computed fields (seq, balance, WAC) are filled by the trigger.
  Future<void> recordTransaction(InkTransaction txn) async {
    final key =
        txn.idempotencyKey.isNotEmpty ? txn.idempotencyKey : _uuid.v4();
    await _db
        .collection(Collections.inkTransactions)
        .doc(key)
        .set(txn.toFirestore());
  }

  /// Manager: enter/correct the cost on a pending receipt → flips to `costed`
  /// and triggers a WAC re-replay server-side.
  Future<void> setPurchaseCost(String txnId, double totalCost) => _db
      .collection(Collections.inkTransactions)
      .doc(txnId)
      .update({'total_cost': totalCost, 'cost_status': InkCostStatus.costed.value});

  /// An item's full ledger, oldest-effective first. Equality query (auto-indexed)
  /// + in-memory sort, so it works without the composite index too.
  Stream<List<InkTransaction>> watchItemLedger(String itemCode) => _db
      .collection(Collections.inkTransactions)
      .where('stock_item_code', isEqualTo: itemCode)
      .snapshots()
      .map((s) {
        final list = s.docs.map(InkTransaction.fromFirestore).toList()
          ..sort((a, b) => a.effectiveAt.compareTo(b.effectiveAt));
        return list;
      });

  /// Manager "pending costs" queue — receipts awaiting a cost.
  Stream<List<InkTransaction>> watchPendingCosts() => _db
      .collection(Collections.inkTransactions)
      .where('cost_status', isEqualTo: InkCostStatus.pending.value)
      .snapshots()
      .map((s) {
        final list = s.docs.map(InkTransaction.fromFirestore).toList()
          ..sort((a, b) => b.effectiveAt.compareTo(a.effectiveAt));
        return list;
      });

  /// Manager review queue — flagged (e.g. negative-balance) movements.
  Stream<List<InkTransaction>> watchFlagged() => _db
      .collection(Collections.inkTransactions)
      .where('flagged_for_review', isEqualTo: true)
      .snapshots()
      .map((s) {
        final list = s.docs.map(InkTransaction.fromFirestore).toList()
          ..sort((a, b) => b.effectiveAt.compareTo(a.effectiveAt));
        return list;
      });

  // ---------------------------------------------------------------------------
  // SUPPLIERS (manager-curated managed list)
  // ---------------------------------------------------------------------------

  Stream<List<InkSupplier>> watchSuppliers({bool activeOnly = true}) => _db
      .collection(Collections.inkSuppliers)
      .snapshots()
      .map((s) {
        final all = s.docs.map(InkSupplier.fromFirestore).toList();
        final filtered = activeOnly ? all.where((x) => x.active).toList() : all;
        filtered.sort((a, b) {
          final c = a.sortOrder.compareTo(b.sortOrder);
          return c != 0
              ? c
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        return filtered;
      });

  Future<void> addSupplier(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _db
        .collection(Collections.inkSuppliers)
        .add(InkSupplier(name: trimmed, sortOrder: 99).toFirestore());
  }

  Future<void> setSupplierActive(String id, bool active) => _db
      .collection(Collections.inkSuppliers)
      .doc(id)
      .update({'active': active});
}
