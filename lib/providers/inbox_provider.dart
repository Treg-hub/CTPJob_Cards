import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/collections.dart';

/// Shared unread inbox items for a clock number (AppBar badge + fleet banner).
/// One listener per clockNo while any consumer is watching.
final unreadInboxItemsProvider = StreamProvider.autoDispose
    .family<List<QueryDocumentSnapshot<Map<String, dynamic>>>, String>(
  (ref, clockNo) {
    if (clockNo.isEmpty) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection(Collections.notificationInbox)
        .doc(clockNo)
        .collection(Collections.notificationInboxItems)
        .where('read', isEqualTo: false)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs);
  },
);

final unreadInboxCountProvider =
    Provider.autoDispose.family<int, String>((ref, clockNo) {
  return ref.watch(unreadInboxItemsProvider(clockNo)).valueOrNull?.length ?? 0;
});
