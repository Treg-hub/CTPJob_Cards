import 'package:cloud_firestore/cloud_firestore.dart';

/// Unwraps Dart/Riverpod async error boxes so operators see the real fault.
Object unwrapAsyncError(Object error) {
  var current = error;
  for (var depth = 0; depth < 4; depth++) {
    try {
      final dynamic d = current;
      final inner = d.error;
      if (inner is Object && inner != current) {
        current = inner;
        continue;
      }
    } catch (_) {}
    break;
  }
  return current;
}

String userFacingError(
  Object error, {
  String? loadFallback,
  String? actionFallback,
}) {
  final root = unwrapAsyncError(error);
  if (root is FirebaseException) {
    final msg = root.message?.trim();
    if (msg != null && msg.isNotEmpty) return msg;
    return root.code;
  }
  if (root is StateError) return root.message;
  final text = root.toString();
  if (text.contains('boxed') && text.contains('stack')) {
    return loadFallback ??
        actionFallback ??
        'Something went wrong. Check your connection and try again.';
  }
  if (text.startsWith('Exception: ')) return text.substring(11);
  if (text.startsWith('Error: ')) return text.substring(7);
  return text;
}