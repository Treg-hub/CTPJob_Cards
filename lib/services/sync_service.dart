import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:hive_flutter/hive_flutter.dart';
import '../models/sync_queue_item.dart';
import 'connectivity_service.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  late final Box<SyncQueueItem> _queueBox;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  Future<void> init() async {
    _queueBox = Hive.box<SyncQueueItem>('sync_queue');   // ← FIXED
    _startListening();
  }

  void _startListening() {
    _connectivitySubscription = ConnectivityService().connectivityStream.listen((results) {
      final isOnline = results.any((result) => result != ConnectivityResult.none);
      if (isOnline) {
        _processQueue();
      }
    });
  }

  Future<void> addToQueue({
    required String collection,
    required String operation,
    required Map<String, dynamic> data,
    String? documentId,
  }) async {
    final id = documentId ?? DateTime.now().millisecondsSinceEpoch.toString();

    final item = SyncQueueItem(
      id: id,
      collection: collection,
      operation: operation,
      data: data,
      createdAt: DateTime.now(),
    );

    await _queueBox.add(item);
    debugPrint('✅ Added to sync queue: $operation $collection');
  }

  Future<void> _processQueue() async {
    if (_queueBox.isEmpty) return;

    final items = _queueBox.values.toList();
    final firestore = FirebaseFirestore.instance;

    for (var item in items) {
      try {
        if (item.collection == 'copper_inventory') {
          final docRef = firestore.doc('copper_inventory/main');
          await docRef.set(item.data, SetOptions(merge: true));
        } else {
          final docRef = firestore.collection(item.collection).doc(item.id);

          if (item.operation == 'create' || item.operation == 'update') {
            await docRef.set(item.data, SetOptions(merge: true));
          } else if (item.operation == 'delete') {
            await docRef.delete();
          }
        }

        await item.delete();
        debugPrint('✅ Synced from queue: ${item.operation} ${item.collection}');
      } catch (e) {
        debugPrint('❌ Failed to sync item: $e');
      }
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
  }
}