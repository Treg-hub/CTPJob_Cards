import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ctp_job_cards/utils/user_facing_error.dart';
import 'package:flutter_test/flutter_test.dart';

class _BoxedError implements Error {
  _BoxedError(this.inner);
  final Object inner;

  Object get error => inner;

  @override
  StackTrace? get stackTrace => null;

  @override
  String toString() =>
      'Dart exception thrown from converted Future. Use the properties `error` '
      'and `stack` to fetch the boxed error and stack trace.';
}

void main() {
  test('unwraps boxed async errors', () {
    final msg = userFacingError(
      _BoxedError(StateError('transaction read after write')),
      actionFallback: 'fallback',
    );
    expect(msg, contains('transaction read after write'));
  });

  test('formats firebase exceptions', () {
    final msg = userFacingError(
      FirebaseException(plugin: 'firestore', code: 'permission-denied'),
    );
    expect(msg, 'permission-denied');
  });
}