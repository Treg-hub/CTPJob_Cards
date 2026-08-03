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
    this.noteNumber,
  });

  final String storagePath;
  final String contentType;
  final String capturedBy;
  final DateTime? capturedAt;
  final String source;

  /// Number printed on the physical transporter form (e.g. WL817898 next to
  /// "Delivery Note"). Operator types this on capture; links paper → receipt.
  final String? noteNumber;

  static InkDeliveryNote? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final path = (m['storagePath'] as String?)?.trim() ?? '';
    if (path.isEmpty) return null;
    final capturedRaw = m['capturedAt'];
    final note = (m['noteNumber'] as String?)?.trim();
    return InkDeliveryNote(
      storagePath: path,
      contentType:
          (m['contentType'] as String?) ?? 'application/octet-stream',
      capturedBy: (m['capturedBy'] as String?) ?? '',
      capturedAt: capturedRaw is Timestamp ? capturedRaw.toDate() : null,
      source: m['source'] == 'pulse' ? 'pulse' : 'mobile',
      noteNumber: (note != null && note.isNotEmpty) ? note : null,
    );
  }
}
