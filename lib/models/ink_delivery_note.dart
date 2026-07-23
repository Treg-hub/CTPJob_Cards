import 'package:cloud_firestore/cloud_firestore.dart';

/// Signed transporter delivery note (POD) on a shipment or local PO.
/// Written only by CF `attachInkDeliveryNote` — clients never set this field.
class InkDeliveryNote {
  const InkDeliveryNote({
    required this.storagePath,
    required this.contentType,
    required this.capturedBy,
    this.capturedAt,
    this.source = 'mobile',
  });

  final String storagePath;
  final String contentType;
  final String capturedBy;
  final DateTime? capturedAt;
  final String source;

  static InkDeliveryNote? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final path = (m['storagePath'] as String?)?.trim() ?? '';
    if (path.isEmpty) return null;
    final capturedRaw = m['capturedAt'];
    return InkDeliveryNote(
      storagePath: path,
      contentType:
          (m['contentType'] as String?) ?? 'application/octet-stream',
      capturedBy: (m['capturedBy'] as String?) ?? '',
      capturedAt: capturedRaw is Timestamp ? capturedRaw.toDate() : null,
      source: m['source'] == 'pulse' ? 'pulse' : 'mobile',
    );
  }
}
