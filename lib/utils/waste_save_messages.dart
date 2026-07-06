/// User-facing copy for queue-first waste saves (guard floor workflow).
abstract final class WasteSaveMessages {
  static String collectionSaved({required int queuedOps}) {
    if (queuedOps > 0) {
      return 'Collection saved on device — $queuedOps item(s) uploading in background';
    }
    return 'Collection saved — syncing in background';
  }

  static String finishLoadingSaved({required int queuedOps}) {
    if (queuedOps > 0) {
      return 'Loading finished on device — $queuedOps item(s) uploading in background';
    }
    return 'Loading finished — syncing in background';
  }

  static String addItemSaved({required int queuedOps}) {
    if (queuedOps > 0) {
      return 'Item saved on device — $queuedOps item(s) uploading in background';
    }
    return 'Item saved — syncing in background';
  }

  static String createLoadSaved({required int queuedOps, String? loadNumber}) {
    final ref = (loadNumber != null && loadNumber.isNotEmpty)
        ? ' ($loadNumber)'
        : '';
    if (queuedOps > 0) {
      return 'Load saved on device$ref — $queuedOps item(s) uploading in background';
    }
    return 'Load saved on device$ref — syncing in background';
  }

  static String submitFailed(Object error, {required int queuedOps}) {
    if (queuedOps > 0) {
      return 'Could not complete save: $error\n\n$queuedOps item(s) are queued on this device — open Queued Operations to retry.';
    }
    return 'Could not save collection: $error\n\nNothing was queued — please try again.';
  }
}