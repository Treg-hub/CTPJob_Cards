import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/utils/stream_retry_policy.dart';

void main() {
  group('retryBackoff', () {
    test('follows the 2s/5s/15s/60s schedule and caps at 60s', () {
      expect(retryBackoff(1), const Duration(seconds: 2));
      expect(retryBackoff(2), const Duration(seconds: 5));
      expect(retryBackoff(3), const Duration(seconds: 15));
      expect(retryBackoff(4), const Duration(seconds: 60));
      expect(retryBackoff(10), const Duration(seconds: 60));
    });

    test('handles zero/negative attempts defensively', () {
      expect(retryBackoff(0), const Duration(seconds: 2));
      expect(retryBackoff(-1), const Duration(seconds: 2));
    });
  });

  group('classifyStreamError', () {
    StreamRetryAction classify(String? code, int attempt) =>
        classifyStreamError(code: code, attempt: attempt);

    test('permission-denied: claims refresh first, then backoff, then park',
        () {
      expect(classify('permission-denied', 1),
          StreamRetryAction.refreshClaimsThenRetry);
      expect(classify('permission-denied', 2),
          StreamRetryAction.refreshClaimsThenRetry);
      expect(classify('permission-denied', 3),
          StreamRetryAction.retryAfterBackoff);
      expect(classify('permission-denied', kMaxBackoffAttempts),
          StreamRetryAction.retryAfterBackoff);
      expect(classify('permission-denied', kMaxBackoffAttempts + 1),
          StreamRetryAction.parkUntilTrigger);
    });

    test('unauthenticated parks until re-login regardless of attempt', () {
      expect(classify('unauthenticated', 1), StreamRetryAction.parkUntilAuth);
      expect(classify('unauthenticated', 99), StreamRetryAction.parkUntilAuth);
    });

    test('likely-permanent codes get two tries then park (never hot-loop)',
        () {
      for (final code in ['failed-precondition', 'invalid-argument']) {
        expect(classify(code, 1), StreamRetryAction.retryAfterBackoff);
        expect(classify(code, 2), StreamRetryAction.retryAfterBackoff);
        expect(classify(code, 3), StreamRetryAction.parkUntilTrigger);
      }
    });

    test('transient / unknown codes backoff then park', () {
      for (final code in ['unavailable', 'deadline-exceeded', 'aborted', null]) {
        expect(classify(code, 1), StreamRetryAction.retryAfterBackoff);
        expect(classify(code, kMaxBackoffAttempts),
            StreamRetryAction.retryAfterBackoff);
        expect(classify(code, kMaxBackoffAttempts + 1),
            StreamRetryAction.parkUntilTrigger);
      }
    });

    test('maxBackoffAttempts override is respected', () {
      expect(
          classifyStreamError(
              code: 'unavailable', attempt: 3, maxBackoffAttempts: 2),
          StreamRetryAction.parkUntilTrigger);
    });
  });
}
