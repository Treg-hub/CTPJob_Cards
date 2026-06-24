import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/collections.dart';
import '../models/waste_stock_item.dart';
import '../models/waste_stock_source.dart';

/// Cross-module writes into [Collections.wasteStock] from Ink and Copper flows.
abstract final class WasteStockCrosslink {
  static String ibcStockDocId(String ibcNumber) => 'stock_ibc_$ibcNumber';

  /// Creates or no-ops an IBC Bins stock row inside an existing Firestore transaction.
  static Future<void> writeIbcStockOnConsume({
    required Transaction txn,
    required FirebaseFirestore db,
    required String ibcNumber,
    required String actorClockNo,
    required String actorName,
    required Timestamp createdAt,
  }) async {
    final stockRef =
        db.collection(Collections.wasteStock).doc(ibcStockDocId(ibcNumber));
    final existing = await txn.get(stockRef);
    if (existing.exists) {
      final data = existing.data();
      final status = (data?['status'] as String?) ?? 'on_site';
      final deleted = data?['is_deleted'] == true;
      if (!deleted && status == 'loaded') {
        throw StateError(
          'IBC $ibcNumber is already on a waste load — resolve waste stock before re-consuming.',
        );
      }
      if (!deleted && status == 'on_site') return;
    }

    txn.set(stockRef, {
      'waste_type': WasteStockTypes.ibcBins,
      'subtype': WasteStockTypes.ibcBins,
      'photos': <String>[],
      'quantity': 1,
      'ibc_number': ibcNumber,
      'source': WasteStockSource.inkConsume.value,
      'source_ref': 'ink_ibc:$ibcNumber',
      'visibility': WasteStockVisibility.all.value,
      'auto_created': true,
      'status': WasteStockStatus.onSite.value,
      'created_by': actorClockNo,
      'created_by_name': actorName,
      'is_deleted': false,
      'created_at': createdAt,
      'updated_at': createdAt,
      'notes': 'Auto-created when IBC consumed in Ink Factory',
    });
  }

  /// Disposes linked IBC stock when ink consumption is voided.
  static Future<void> disposeIbcStockOnVoid({
    required WriteBatch batch,
    required FirebaseFirestore db,
    required String ibcNumber,
    required Timestamp updatedAt,
  }) async {
    final stockRef =
        db.collection(Collections.wasteStock).doc(ibcStockDocId(ibcNumber));
    batch.set(
      stockRef,
      {
        'is_deleted': true,
        'status': WasteStockStatus.disposed.value,
        'updated_at': updatedAt,
        'notes': 'Auto-disposed: ink IBC consumption voided',
      },
      SetOptions(merge: true),
    );
  }

  /// Guard before voiding ink consumption — stock must still be on_site.
  static Future<void> assertIbcStockVoidable(FirebaseFirestore db, String ibcNumber) async {
    final snap = await db
        .collection(Collections.wasteStock)
        .doc(ibcStockDocId(ibcNumber))
        .get();
    if (!snap.exists) return;
    final data = snap.data();
    if (data?['is_deleted'] == true) return;
    final status = (data?['status'] as String?) ?? 'on_site';
    if (status == 'loaded') {
      throw StateError(
        'Cannot void IBC consumption — empty bin is already on a waste load.',
      );
    }
  }
}