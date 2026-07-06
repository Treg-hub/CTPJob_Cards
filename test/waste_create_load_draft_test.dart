import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/models/waste_item.dart';
import 'package:ctp_job_cards/utils/waste_create_load_draft.dart';

void main() {
  group('WasteCreateLoadDraft', () {
    test('hasContent detects any meaningful field', () {
      expect(
        WasteCreateLoadDraft.hasContent(driverName: '', vehicleReg: ''),
        isFalse,
      );
      expect(
        WasteCreateLoadDraft.hasContent(
          driverName: 'Sam',
          vehicleReg: '',
        ),
        isTrue,
      );
      expect(
        WasteCreateLoadDraft.hasContent(
          driverName: '',
          vehicleReg: '',
          items: [
            WasteItem(loadId: 'temp', subtype: 'Paper', weightKg: 10),
          ],
        ),
        isTrue,
      );
    });

    test('toJson and fromJsonString round-trip core fields', () {
      final json = WasteCreateLoadDraft.toJson(
        createSubmitRef: 'submit-ref-abc',
        driverName: 'Sam Naidoo',
        vehicleReg: 'ABC123GP',
        trailerReg: 'TRL99',
        paperDocumentRef: 'DOC-42',
        notes: 'Gate 2',
        contractorId: 'contractor-1',
        selectedTypeIds: ['type-a', 'type-b'],
        timeIn: '08:30',
        timeOut: '09:15',
        items: [
          WasteItem(
            loadId: 'temp',
            subtype: 'Paper Waste',
            weightKg: 120,
            quantity: 2,
            photos: const [],
          ),
        ],
        selectedStockIds: ['stock-1'],
        selectedStockSnapshots: [
          {
            'id': 'stock-1',
            'waste_type': 'Paper Waste',
            'subtype': 'Mixed',
            'status': 'on_site',
            'is_deleted': false,
          },
        ],
      );

      final restored = WasteCreateLoadDraft.fromJsonString(jsonEncode(json));
      expect(restored, isNotNull);
      expect(restored!.createSubmitRef, 'submit-ref-abc');
      expect(restored.driverName, 'Sam Naidoo');
      expect(restored.vehicleReg, 'ABC123GP');
      expect(restored.trailerReg, 'TRL99');
      expect(restored.paperDocumentRef, 'DOC-42');
      expect(restored.notes, 'Gate 2');
      expect(restored.contractorId, 'contractor-1');
      expect(restored.selectedTypeIds, ['type-a', 'type-b']);
      expect(restored.timeIn, '08:30');
      expect(restored.timeOut, '09:15');
      expect(restored.selectedStockIds, ['stock-1']);
      expect(restored.selectedStockSnapshots, hasLength(1));
      expect(restored.selectedStockSnapshots.first['id'], 'stock-1');
      expect(restored.items, hasLength(1));
      expect(restored.items.first.subtype, 'Paper Waste');
      expect(restored.items.first.weightKg, 120);
    });

    test('fromJsonString drops photo paths that no longer exist', () {
      final payload = {
        'driver_name': 'Sam',
        'vehicle_reg': 'ABC',
        'selected_type_ids': <String>[],
        'selected_stock_ids': <String>[],
        'items': [
          {
            'subtype': 'Paper',
            'weight_kg': 10,
            'photos': ['/tmp/does-not-exist.jpg'],
          },
        ],
      };

      final restored =
          WasteCreateLoadDraft.fromJsonString(jsonEncode(payload));
      expect(restored, isNotNull);
      expect(restored!.items.single.photos, isEmpty);
    });



    test('prefsKey is clock-scoped', () {
      expect(WasteCreateLoadDraft.prefsKey('22'), 'wasteCreateLoadDraft_22');
      expect(WasteCreateLoadDraft.prefsKey(null), 'wasteCreateLoadDraft_unknown');
    });
  });

  testWidgets('controllers retain text across parent setState', (tester) async {
    final driverCtrl = TextEditingController(text: 'Sam');
    final vehicleCtrl = TextEditingController(text: 'ABC123GP');
    var counter = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: Column(
                children: [
                  TextFormField(
                    controller: driverCtrl,
                    decoration: const InputDecoration(labelText: 'Driver'),
                  ),
                  TextFormField(
                    controller: vehicleCtrl,
                    decoration: const InputDecoration(labelText: 'Vehicle'),
                  ),
                  ElevatedButton(
                    onPressed: () => setState(() => counter++),
                    child: Text('Rebuild $counter'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('ABC123GP'), findsOneWidget);

    await tester.tap(find.text('Rebuild 0'));
    await tester.pump();

    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('ABC123GP'), findsOneWidget);
  });
}