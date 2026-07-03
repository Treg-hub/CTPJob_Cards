import 'package:flutter_test/flutter_test.dart';

import 'package:ctp_job_cards/constants/ink_toloul.dart';
import 'package:ctp_job_cards/models/ink_settings.dart';
import 'package:ctp_job_cards/models/ink_stock_item.dart';

InkStockItem _toloul({
  double current = 10000,
  double? factory,
  double? lurgi,
}) =>
    InkStockItem(
      itemCode: kToloulItemCode,
      displayName: 'Toloul',
      unit: 'LTS',
      itemClass: InkItemClass.solvent,
      currentBalance: current,
      factoryTankBalance: factory,
      lurgiBalance: lurgi,
      weightedAverageCost: 10,
      lastUpdated: DateTime(2026, 6, 1),
    );

void main() {
  test('toloul operational balance prefers factory tank cache', () {
    final item = _toloul(current: 10000, factory: 6000, lurgi: 4000);
    expect(item.operationalBalance, 6000);
    expect(item.isToloul, isTrue);
  });

  test('toloul without split falls back to consolidated balance', () {
    final item = _toloul(current: 8000);
    expect(item.operationalBalance, 8000);
  });

  test('ink settings default lurgi low threshold', () {
    expect(InkSettings.defaults.toloulLurgiLowLitres,
        kDefaultToloulLurgiLowLitres);
  });
}