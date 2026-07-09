import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/utils/list_load_state.dart';

void main() {
  group('decideListLoadState (full truth table)', () {
    ListLoadState decide(bool hasSnapshot, bool isEmpty, bool isFromCache) =>
        decideListLoadState(
            hasSnapshot: hasSnapshot,
            isEmpty: isEmpty,
            isFromCache: isFromCache);

    test('no snapshot is always loading', () {
      expect(decide(false, true, true), ListLoadState.loading);
      expect(decide(false, true, false), ListLoadState.loading);
      expect(decide(false, false, true), ListLoadState.loading);
      expect(decide(false, false, false), ListLoadState.loading);
    });

    test('items render as data regardless of cache origin', () {
      expect(decide(true, false, true), ListLoadState.data);
      expect(decide(true, false, false), ListLoadState.data);
    });

    test('empty-from-cache waits for the server; empty-from-server is empty',
        () {
      // The core fix: a cold cache must never masquerade as "no jobs".
      expect(decide(true, true, true), ListLoadState.waitingForServer);
      expect(decide(true, true, false), ListLoadState.empty);
    });
  });

  group('shouldRearmActiveJobsOnResume', () {
    test('re-arms when no snapshot yet', () {
      expect(
        shouldRearmActiveJobsOnResume(
          hasSnapshot: false,
          isEmpty: true,
          isFromCache: true,
        ),
        isTrue,
      );
    });

    test('re-arms on cache-only empty snapshot', () {
      expect(
        shouldRearmActiveJobsOnResume(
          hasSnapshot: true,
          isEmpty: true,
          isFromCache: true,
        ),
        isTrue,
      );
    });

    test('does not re-arm when server confirmed empty or data present', () {
      expect(
        shouldRearmActiveJobsOnResume(
          hasSnapshot: true,
          isEmpty: true,
          isFromCache: false,
        ),
        isFalse,
      );
      expect(
        shouldRearmActiveJobsOnResume(
          hasSnapshot: true,
          isEmpty: false,
          isFromCache: true,
        ),
        isFalse,
      );
    });
  });

  group('merged stream helpers', () {
    test('allStreamSidesReady requires every side', () {
      expect(allStreamSidesReady([true, true]), isTrue);
      expect(allStreamSidesReady([true, false]), isFalse);
    });

    test('mergedIsFromCache waits for all sides then ORs cache flags', () {
      expect(
        mergedIsFromCache(
          sidesHaveSnapshot: [true, false],
          sidesFromCache: [false, true],
        ),
        isTrue,
      );
      expect(
        mergedIsFromCache(
          sidesHaveSnapshot: [true, true],
          sidesFromCache: [false, false],
        ),
        isFalse,
      );
      expect(
        mergedIsFromCache(
          sidesHaveSnapshot: [true, true],
          sidesFromCache: [false, true],
        ),
        isTrue,
      );
    });
  });

  group('shouldTreatEmployeeMissing', () {
    test('only a server-confirmed absence counts as missing', () {
      expect(shouldTreatEmployeeMissing(exists: false, isFromCache: false),
          isTrue);
      expect(shouldTreatEmployeeMissing(exists: false, isFromCache: true),
          isFalse); // offline cache miss — never log out on this
      expect(shouldTreatEmployeeMissing(exists: true, isFromCache: false),
          isFalse);
      expect(shouldTreatEmployeeMissing(exists: true, isFromCache: true),
          isFalse);
    });
  });
}
