import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/models/waste_type.dart';

void main() {
  test('Board K4 catalogue name shows as Board / K4 bin on chips', () {
    const type = WasteType(id: 'x', mainType: 'Open Bin(Board K4)');
    expect(type.chipLabel, 'Board / K4 bin');
    expect(type.mainType, 'Open Bin(Board K4)');
  });

  test('Open Bin label is unchanged', () {
    const type = WasteType(id: 'y', mainType: 'Open Bin');
    expect(type.chipLabel, 'Open Bin');
  });
}
