import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/collections.dart';
import '../models/waste_stock_item.dart';
import '../models/waste_stock_source.dart';

/// Result of reading the current open IBC pool inside a transaction —
/// see [WasteStockCrosslink.readIbcPool].
class IbcPoolRead {
  const IbcPoolRead({
    required this.pointerRef,
    required this.poolId,
    required this.poolSnap,
  });

  final DocumentReference<Map<String, dynamic>> pointerRef;
  final String? poolId;
  final DocumentSnapshot<Map<String, dynamic>>? poolSnap;
}

/// Cross-module writes into [Collections.wasteStock] from Ink and Copper flows.
///
/// IBC consumption accumulates into one running "pool" doc per open batch
/// (`source: ink_consume_pool`, `quantity` increments, `linked_ibc_numbers`
/// tracks the underlying physical IBCs) instead of one doc per IBC. The open
/// pool is located via a deterministic pointer doc
/// (`waste_stock_pool_pointers/ibc_bins`) rather than a query, because a
/// transactional *query* for "does a pool doc exist" does not serialize
/// against a concurrent transaction doing the same query — two racing
/// consumes could both see "none" and both create a pool, fragmenting the
/// count. A transactional *read of a known doc* does serialize correctly
/// (Firestore retries the whole transaction on a conflicting write), the same
/// pattern already used for `waste_counters/global` numbering.
abstract final class WasteStockCrosslink {
  static DocumentReference<Map<String, dynamic>> ibcPoolPointerRef(
    FirebaseFirestore db,
  ) =>
      db.collection(Collections.wasteStockPoolPointers).doc(kIbcPoolPointerDocId);

  /// Reads the pointer doc and (if it points somewhere) the pointed-to pool
  /// doc. Must be called — and awaited — before any writes in the caller's
  /// transaction (Firestore requires all transaction reads before writes).
  static Future<IbcPoolRead> readIbcPool({
    required Transaction txn,
    required FirebaseFirestore db,
  }) async {
    final pointerRef = ibcPoolPointerRef(db);
    final pointerSnap = await txn.get(pointerRef);
    final poolId = pointerSnap.data()?['current_pool_stock_id'] as String?;
    DocumentSnapshot<Map<String, dynamic>>? poolSnap;
    if (poolId != null) {
      poolSnap = await txn.get(db.collection(Collections.wasteStock).doc(poolId));
    }
    return IbcPoolRead(pointerRef: pointerRef, poolId: poolId, poolSnap: poolSnap);
  }

  /// Accumulates one consumed IBC into the open pool (incrementing it), or
  /// starts a fresh pool doc + repoints the pointer if none is currently open
  /// (none yet, or the pointer is stale — pointing at a doc that's since been
  /// fully taken onto a load). [pool] must come from [readIbcPool] called
  /// earlier in the same transaction. Caller is responsible for the
  /// already-consumed/already-damaged idempotency check (see
  /// `InkService.transferIbc`) — this method always accumulates.
  static void applyIbcPoolConsume({
    required Transaction txn,
    required FirebaseFirestore db,
    required IbcPoolRead pool,
    required String ibcNumber,
    required String actorClockNo,
    required String actorName,
    required Timestamp createdAt,
  }) {
    final poolSnap = pool.poolSnap;
    final poolData = (poolSnap != null && poolSnap.exists) ? poolSnap.data() : null;
    final poolOpen = poolData != null &&
        poolData['is_deleted'] != true &&
        (poolData['status'] as String? ?? 'on_site') == 'on_site';

    if (poolOpen) {
      final poolRef = db.collection(Collections.wasteStock).doc(pool.poolId);
      txn.update(poolRef, {
        'quantity': FieldValue.increment(1),
        'linked_ibc_numbers': FieldValue.arrayUnion([ibcNumber]),
        'updated_at': createdAt,
      });
      return;
    }

    final newPoolRef = db.collection(Collections.wasteStock).doc();
    txn.set(newPoolRef, {
      'waste_type': WasteStockTypes.ibcBins,
      'subtype': WasteStockTypes.ibcBins,
      'photos': <String>[],
      'quantity': 1,
      'linked_ibc_numbers': [ibcNumber],
      'source': WasteStockSource.inkConsumePool.value,
      'source_ref': 'ink_ibc_pool',
      'visibility': WasteStockVisibility.all.value,
      'auto_created': true,
      'status': WasteStockStatus.onSite.value,
      'created_by': actorClockNo,
      'created_by_name': actorName,
      'is_deleted': false,
      'created_at': createdAt,
      'updated_at': createdAt,
      'notes': 'Auto-created/accumulated when IBCs consumed in Ink Factory',
    });
    txn.set(pool.pointerRef, {
      'current_pool_stock_id': newPoolRef.id,
      'updated_at': createdAt,
    }, SetOptions(merge: true));
  }

  /// Clears the pointer if it currently points at [stockId] — call this in
  /// the same transaction that takes the *entire* remaining quantity of a
  /// pool doc onto a load (status flips to `loaded`), so the next IBC
  /// consume starts a fresh pool instead of accumulating into a doc that's
  /// no longer on-site. Partial takes (split) don't need this — the pool
  /// doc keeps a nonzero remaining quantity and stays the open pool.
  static void clearIbcPoolPointerIfPointsTo({
    required Transaction txn,
    required IbcPoolRead pool,
    required String stockId,
  }) {
    if (pool.poolId == stockId) {
      txn.set(pool.pointerRef, {'current_pool_stock_id': null}, SetOptions(merge: true));
    }
  }

  /// Locates the (at most one, expected) non-deleted `waste_stock` doc that
  /// currently lists [ibcNumber] in its `linked_ibc_numbers` — replaces the
  /// old deterministic `stock_ibc_{n}` doc-id lookup, since docs are no
  /// longer 1:1 with IBC numbers under the pool model. Returns null if the
  /// IBC was never pooled (e.g. it was marked damaged at consume time) or has
  /// already been fully removed.
  static Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _findStockDocForIbc(
    FirebaseFirestore db,
    String ibcNumber,
  ) async {
    final snap = await db
        .collection(Collections.wasteStock)
        .where('linked_ibc_numbers', arrayContains: ibcNumber)
        .where('is_deleted', isEqualTo: false)
        .limit(1)
        .get();
    return snap.docs.isEmpty ? null : snap.docs.first;
  }

  /// Disposes (or decrements) linked IBC stock when ink consumption is
  /// voided. If the IBC is the sole unit represented by its stock doc, the
  /// doc is fully disposed (matches prior behavior); if it's part of a
  /// multi-unit pool/split doc, only that one unit is removed (quantity
  /// decremented, its number dropped from `linked_ibc_numbers`) — the rest of
  /// the doc's units are unaffected.
  static Future<void> disposeIbcStockOnVoid({
    required WriteBatch batch,
    required FirebaseFirestore db,
    required String ibcNumber,
    required Timestamp updatedAt,
  }) async {
    final doc = await _findStockDocForIbc(db, ibcNumber);
    if (doc == null) return;
    final data = doc.data();
    final quantity = (data['quantity'] as num?)?.toInt() ?? 1;
    final ref = db.collection(Collections.wasteStock).doc(doc.id);
    if (quantity <= 1) {
      batch.set(
        ref,
        {
          'is_deleted': true,
          'status': WasteStockStatus.disposed.value,
          'updated_at': updatedAt,
          'notes': 'Auto-disposed: ink IBC consumption voided',
        },
        SetOptions(merge: true),
      );
    } else {
      batch.update(ref, {
        'quantity': FieldValue.increment(-1),
        'linked_ibc_numbers': FieldValue.arrayRemove([ibcNumber]),
        'updated_at': updatedAt,
      });
    }
  }

  /// Guard before voiding ink consumption — the IBC's stock unit must still
  /// be on_site (not already on a `loaded` waste load).
  static Future<void> assertIbcStockVoidable(FirebaseFirestore db, String ibcNumber) async {
    final doc = await _findStockDocForIbc(db, ibcNumber);
    if (doc == null) return;
    final status = (doc.data()['status'] as String?) ?? 'on_site';
    if (status == 'loaded') {
      throw StateError(
        'Cannot void IBC consumption — empty bin is already on a waste load.',
      );
    }
  }
}
