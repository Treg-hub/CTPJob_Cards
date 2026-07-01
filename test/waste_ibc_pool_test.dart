import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/models/ink_ibc.dart';
import 'package:ctp_job_cards/models/waste_stock_item.dart';
import 'package:ctp_job_cards/models/waste_stock_source.dart';

// Pure model-level coverage for the consolidated IBC waste-pool feature.
//
// The pool/split/damaged-removal logic itself (WasteStockCrosslink,
// WasteService.splitPoolStock/removeDamagedIbcUnits, InkService.transferIbc's
// markDamaged branch) all require a live Firestore transaction — this repo
// has no emulator harness for transactional Firestore logic (confirmed: the
// existing test suite's WasteService() construction throws [core/no-app] the
// moment Firebase isn't initialized, and there's no fake_cloud_firestore or
// emulator-backed test setup anywhere in test/). What IS testable without
// Firebase — the new model fields and their (de)serialization contracts —
// is covered here; the transactional logic is exercised by the manual smoke
// test in the plan instead.

void main() {
  group('WasteStockSource.inkConsumePool', () {
    test('round-trips via fromString/value', () {
      expect(WasteStockSource.inkConsumePool.value, 'ink_consume_pool');
      expect(WasteStockSource.fromString('ink_consume_pool'),
          WasteStockSource.inkConsumePool);
    });
  });

  group('WasteStockItem — linkedIbcNumbers + damaged (consolidated IBC pool)', () {
    WasteStockItem baseItem({List<String>? linkedIbcNumbers, bool? damaged}) {
      return WasteStockItem(
        wasteType: WasteStockTypes.ibcBins,
        subtype: WasteStockTypes.ibcBins,
        quantity: 3,
        source: WasteStockSource.inkConsumePool,
        linkedIbcNumbers: linkedIbcNumbers ?? const ['101', '102', '103'],
        damaged: damaged ?? false,
        createdBy: 'C1',
        createdByName: 'Operator',
        createdAt: DateTime.now(),
      );
    }

    test('defaults: linkedIbcNumbers empty, damaged false', () {
      final item = WasteStockItem(
        wasteType: WasteStockTypes.ibcBins,
        subtype: WasteStockTypes.ibcBins,
        createdBy: 'C1',
        createdByName: 'Operator',
        createdAt: DateTime.now(),
      );
      expect(item.linkedIbcNumbers, isEmpty);
      expect(item.damaged, isFalse);
    });

    test('toFirestore includes linked_ibc_numbers when non-empty, omits when empty', () {
      final withLinks = baseItem();
      final map = withLinks.toFirestore();
      expect(map['linked_ibc_numbers'], ['101', '102', '103']);
      expect(map['damaged'], false);

      final noLinks = baseItem(linkedIbcNumbers: const []);
      expect(noLinks.toFirestore().containsKey('linked_ibc_numbers'), isFalse);
    });

    test('toFirestore always writes damaged (true or false) — never omitted', () {
      expect(baseItem(damaged: true).toFirestore()['damaged'], true);
      expect(baseItem(damaged: false).toFirestore()['damaged'], false);
    });

    test('copyWith updates quantity + linkedIbcNumbers independently (partial damaged-removal shape)', () {
      final item = baseItem();
      // Mirrors what removeDamagedIbcUnits' caller does locally after a
      // partial removal: drop N numbers, reduce quantity by N.
      final reduced = item.copyWith(
        quantity: item.quantity - 1,
        linkedIbcNumbers: item.linkedIbcNumbers.skip(1).toList(),
      );
      expect(reduced.quantity, 2);
      expect(reduced.linkedIbcNumbers, ['102', '103']);
      // Untouched fields preserved.
      expect(reduced.wasteType, item.wasteType);
      expect(reduced.source, WasteStockSource.inkConsumePool);
    });
  });

  group('InkIbc — damage fields (consume-time exclusion + Begin Collection removal)', () {
    InkIbc baseIbc({bool damageFlag = false, String? damageReason}) {
      return InkIbc(
        ibcNumber: '101',
        itemCode: 'yellow',
        kg: 200,
        receivedDate: DateTime(2026, 1, 1),
        damageFlag: damageFlag,
        damageReason: damageReason,
        damageRecordedAt: damageFlag ? DateTime(2026, 6, 30) : null,
        damageRecordedBy: damageFlag ? 'C1' : null,
      );
    }

    test('defaults: damageFlag false, reason/recordedAt/recordedBy null', () {
      final ibc = InkIbc(
        ibcNumber: '101',
        itemCode: 'yellow',
        kg: 200,
        receivedDate: DateTime(2026, 1, 1),
      );
      expect(ibc.damageFlag, isFalse);
      expect(ibc.damageReason, isNull);
      expect(ibc.damageRecordedAt, isNull);
      expect(ibc.damageRecordedBy, isNull);
    });

    test('toFirestore omits all damage_* keys when not damaged', () {
      final map = baseIbc().toFirestore();
      expect(map.containsKey('damage_flag'), isFalse);
      expect(map.containsKey('damage_reason'), isFalse);
      expect(map.containsKey('damage_recorded_at'), isFalse);
      expect(map.containsKey('damage_recorded_by'), isFalse);
    });

    test('toFirestore includes all damage_* keys when damaged', () {
      final map = baseIbc(damageFlag: true, damageReason: 'split seam').toFirestore();
      expect(map['damage_flag'], true);
      expect(map['damage_reason'], 'split seam');
      expect(map.containsKey('damage_recorded_at'), isTrue);
      expect(map['damage_recorded_by'], 'C1');
    });
  });
}
