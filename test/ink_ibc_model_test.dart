import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ctp_job_cards/models/ink_ibc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseTimestamp accepts ISO strings', () {
    final dt = InkIbc.parseTimestamp('2024-06-15T10:30:00.000Z');
    expect(dt, isNotNull);
    expect(dt!.toUtc(), DateTime.utc(2024, 6, 15, 10, 30));
  });

  test('parseTimestamp accepts Firestore Timestamp', () {
    final date = DateTime(2025, 1, 2, 8, 0);
    final ts = Timestamp.fromDate(date);
    expect(InkIbc.parseTimestamp(ts), date);
  });

  test('parseDouble coerces strings and numbers', () {
    expect(InkIbc.parseDouble('2964.5'), 2964.5);
    expect(InkIbc.parseDouble(100), 100.0);
    expect(InkIbc.parseDouble(null), 0);
  });
}