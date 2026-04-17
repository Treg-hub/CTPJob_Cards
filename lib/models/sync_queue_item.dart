import 'package:hive_flutter/hive_flutter.dart';

part 'sync_queue_item.g.dart';

@HiveType(typeId: 10)
class SyncQueueItem extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String collection; // 'job_cards' or 'copper_transactions'

  @HiveField(2)
  final String operation; // 'create', 'update', 'delete'

  @HiveField(3)
  final Map<String, dynamic> data;

  @HiveField(4)
  final DateTime createdAt;

  SyncQueueItem({
    required this.id,
    required this.collection,
    required this.operation,
    required this.data,
    required this.createdAt,
  });
}