import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/models/press_live_access.dart';

void main() {
  group('PressLiveAccess.allows', () {
    test('clock list', () {
      const access = PressLiveAccess(clockNos: ['22', '105']);
      expect(
        access.allows(clockNo: '105', department: 'Pressroom', position: 'Foreman'),
        isTrue,
      );
      expect(
        access.allows(clockNo: '99', department: 'Pressroom', position: 'Foreman'),
        isFalse,
      );
    });

    test('whole department', () {
      const access = PressLiveAccess(departments: ['Pressroom']);
      expect(
        access.allows(clockNo: '99', department: 'Pressroom', position: 'Operator'),
        isTrue,
      );
      expect(
        access.allows(clockNo: '99', department: 'Workshop', position: 'Foreman'),
        isFalse,
      );
    });

    test('whole position is case-insensitive', () {
      const access = PressLiveAccess(positions: ['Foreman', 'Shift Leader']);
      expect(
        access.allows(clockNo: '1', department: 'Pressroom', position: 'foreman'),
        isTrue,
      );
      expect(
        access.allows(clockNo: '1', department: 'Despatch', position: 'Shift Leader'),
        isTrue,
      );
      expect(
        access.allows(clockNo: '1', department: 'Pressroom', position: 'Operator'),
        isFalse,
      );
    });

    test('fromMap ignores blanks and keeps first casing', () {
      final access = PressLiveAccess.fromMap({
        'clock_nos': [' 22 ', '', '22'],
        'departments': ['Pressroom'],
        'positions': ['Co Ordinator'],
      });
      expect(access.clockNos, ['22']);
      expect(
        access.allows(clockNo: 'x', department: 'x', position: 'co ordinator'),
        isTrue,
      );
    });
  });
}
