/// Maps a caught exception to a guard-friendly message. Falls back to a
/// generic retry prompt rather than surfacing raw exception text (e.g.
/// Firebase's "[cloud_firestore/permission-denied] ...").
String friendlySecurityError(Object e) {
  final msg = e.toString().toLowerCase();
  if (msg.contains('unauthenticated') || msg.contains('permission-denied')) {
    return 'You do not have permission for this action. Contact your manager.';
  }
  if (msg.contains('network') ||
      msg.contains('socketexception') ||
      msg.contains('timeout')) {
    return 'Network issue — entry has been queued and will sync when back online.';
  }
  if (msg.contains('failed-precondition') || msg.contains('invalid-argument')) {
    return 'Some details were missing or invalid — please check the form and try again.';
  }
  return 'Something went wrong. Please try again, or ask your manager if it keeps happening.';
}
