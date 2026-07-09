/// Pure decisions for "what should a Firestore-backed list show?" — kept free
/// of Flutter/Firebase imports so the truth tables are unit-testable
/// (see test/list_load_state_test.dart).
///
/// Background: with offline persistence enabled, the FIRST snapshot after a
/// cold start can come from an empty local cache. Rendering that as the empty
/// state ("No recent jobs available", "Active (0)") looks like the app is
/// broken when it is merely offline. Only a server-backed snapshot may show
/// the true empty state.
library;

enum ListLoadState {
  /// No snapshot yet — show skeletons/spinner.
  loading,

  /// Snapshot exists but is empty AND from cache — the server hasn't answered
  /// yet, so this may not be truly empty. Show skeletons + "waiting for
  /// connection" hint, never the empty state.
  waitingForServer,

  /// Server-confirmed empty — safe to show the real empty state.
  empty,

  /// Has items — render them (cached items are fine to show).
  data,
}

ListLoadState decideListLoadState({
  required bool hasSnapshot,
  required bool isEmpty,
  required bool isFromCache,
}) {
  if (!hasSnapshot) return ListLoadState.loading;
  if (!isEmpty) return ListLoadState.data;
  return isFromCache ? ListLoadState.waitingForServer : ListLoadState.empty;
}

/// Multi-stream merges (My Work, View Jobs, Daily Review) must not emit until
/// every side has seen at least one snapshot — otherwise a slow/parked query
/// leaves `isFromCache` stuck true and the UI spins forever.
bool allStreamSidesReady(Iterable<bool> sidesHaveSnapshot) =>
    sidesHaveSnapshot.every((ready) => ready);

/// After [allStreamSidesReady], true when any side is still cache-only.
bool mergedIsFromCache({
  required Iterable<bool> sidesHaveSnapshot,
  required Iterable<bool> sidesFromCache,
}) {
  if (!allStreamSidesReady(sidesHaveSnapshot)) return true;
  return sidesFromCache.any((fromCache) => fromCache);
}

/// Whether a missing employee doc should be treated as a real deletion.
/// A cache miss while offline reports `exists == false` without the server
/// ever being asked — acting on that would wrongly log the user out.
bool shouldTreatEmployeeMissing({
  required bool exists,
  required bool isFromCache,
}) {
  return !exists && !isFromCache;
}

/// Re-arm the active-jobs listener after resume when it is still showing the
/// loading skeleton or a cache-only empty snapshot.
bool shouldRearmActiveJobsOnResume({
  required bool hasSnapshot,
  required bool isEmpty,
  required bool isFromCache,
}) {
  if (!hasSnapshot) return true;
  return isEmpty && isFromCache;
}
