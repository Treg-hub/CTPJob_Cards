/// Pure retry policy for resilient Firestore streams — no Firebase imports so
/// the whole decision table is unit-testable (see test/stream_retry_policy_test.dart).
///
/// Background: Firestore terminates a snapshot listener PERMANENTLY on
/// permission-denied — it never retries on its own. At cold start the home
/// streams race the custom-claims/token refresh, so a transient denial used
/// to kill them until the app was force-restarted ("logged in but nothing
/// appearing"). The wrapper in services/resilient_stream.dart consults this
/// policy to decide how to bring a dead stream back.
library;

enum StreamRetryAction {
  /// Re-subscribe after [retryBackoff] for the current attempt.
  retryAfterBackoff,

  /// Refresh custom claims (which force-refreshes the ID token), then
  /// re-subscribe — the likely cause is rules not seeing fresh claims yet.
  refreshClaimsThenRetry,

  /// Stop timed retries; wait for an external trigger (connectivity restored,
  /// claims refreshed, app resumed, re-login) before trying again.
  parkUntilTrigger,

  /// Wait specifically for a signed-in auth state — the session itself is
  /// gone, and the session banner owns the user-facing recovery.
  parkUntilAuth,
}

/// Attempts are 1-based. Capped so a parked stream that gets re-triggered
/// hourly never waits longer than a minute once it starts retrying again.
Duration retryBackoff(int attempt) {
  switch (attempt) {
    case <= 1:
      return const Duration(seconds: 2);
    case 2:
      return const Duration(seconds: 5);
    case 3:
      return const Duration(seconds: 15);
    default:
      return const Duration(seconds: 60);
  }
}

/// Default number of timed attempts before a stream parks and waits for an
/// external trigger.
const int kMaxBackoffAttempts = 5;

/// Decide how to react to a stream error. [code] is the Firestore/Firebase
/// error code string (null for non-Firebase errors, treated as transient).
/// [attempt] is 1-based: the value AFTER incrementing for this failure.
StreamRetryAction classifyStreamError({
  required String? code,
  required int attempt,
  int maxBackoffAttempts = kMaxBackoffAttempts,
}) {
  switch (code) {
    case 'permission-denied':
      // First two failures: most likely the claims/token race at startup —
      // refresh claims before retrying. After that, plain backoff, then park.
      if (attempt <= 2) return StreamRetryAction.refreshClaimsThenRetry;
      return attempt <= maxBackoffAttempts
          ? StreamRetryAction.retryAfterBackoff
          : StreamRetryAction.parkUntilTrigger;
    case 'unauthenticated':
      return StreamRetryAction.parkUntilAuth;
    case 'failed-precondition':
    case 'invalid-argument':
      // Likely permanent (missing index, malformed query) — a couple of tries
      // in case of server flakiness, then park. Never hot-loop on these.
      return attempt <= 2
          ? StreamRetryAction.retryAfterBackoff
          : StreamRetryAction.parkUntilTrigger;
    default:
      // unavailable, deadline-exceeded, aborted, unknown, non-Firebase (null):
      // transient — timed retries, then park until a trigger.
      return attempt <= maxBackoffAttempts
          ? StreamRetryAction.retryAfterBackoff
          : StreamRetryAction.parkUntilTrigger;
  }
}
