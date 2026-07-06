import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/utils/mobile_scanner_lifecycle.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  group('mobileScannerStartRetryDelay', () {
    test('doubles from 200ms up to a cap', () {
      expect(mobileScannerStartRetryDelay(0), const Duration(milliseconds: 200));
      expect(mobileScannerStartRetryDelay(1), const Duration(milliseconds: 400));
      expect(mobileScannerStartRetryDelay(4), const Duration(milliseconds: 3200));
      expect(mobileScannerStartRetryDelay(99), const Duration(milliseconds: 3200));
    });
  });

  group('isMobileScannerInitializingError', () {
    test('matches controllerInitializing code', () {
      final error = MobileScannerException(
        errorCode: MobileScannerErrorCode.controllerInitializing,
      );
      expect(isMobileScannerInitializingError(error), isTrue);
    });

    test('rejects other scanner errors', () {
      final error = MobileScannerException(
        errorCode: MobileScannerErrorCode.controllerNotAttached,
      );
      expect(isMobileScannerInitializingError(error), isFalse);
      expect(isMobileScannerInitializingError(Exception('x')), isFalse);
    });
  });
}