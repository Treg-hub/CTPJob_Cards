import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/utils/barcode_payload_util.dart';

void main() {
  group('BarcodePayloadUtil', () {
    test('encodeBytesPayload uses base64 prefix', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      expect(
        BarcodePayloadUtil.encodeBytesPayload(bytes),
        'base64:${base64Encode(bytes)}',
      );
    });

    test('decodeBytesPayload round-trips', () {
      final bytes = Uint8List.fromList(List.generate(720, (i) => i % 256));
      final encoded = BarcodePayloadUtil.encodeBytesPayload(bytes);
      expect(BarcodePayloadUtil.decodeBytesPayload(encoded), bytes);
    });

    test('displayPayload summarizes binary captures', () {
      final encoded = BarcodePayloadUtil.encodeBytesPayload(
        Uint8List.fromList(List.filled(720, 0xab)),
      );
      expect(
        BarcodePayloadUtil.displayPayload(encoded),
        contains('Encrypted barcode (720 bytes)'),
      );
    });
  });
}