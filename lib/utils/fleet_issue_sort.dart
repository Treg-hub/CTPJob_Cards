import '../models/fleet_issue.dart';

/// Sort issues: OOS first, then high/medium/low, then newest first within tier.
List<FleetIssue> sortFleetIssuesByPriority(List<FleetIssue> issues) {
  final copy = List<FleetIssue>.from(issues);
  copy.sort((a, b) {
    final bySeverity =
        a.severity.sortOrder.compareTo(b.severity.sortOrder);
    if (bySeverity != 0) return bySeverity;
    final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
    final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
    return bTime.compareTo(aTime);
  });
  return copy;
}

List<FleetIssue> pinnedOpenOosIssues(List<FleetIssue> openIssues) {
  return openIssues
      .where((i) => i.severity == FleetIssueSeverity.outOfService)
      .toList();
}

List<FleetIssue> openIssuesExcludingPinned(
  List<FleetIssue> openIssues,
  List<FleetIssue> pinned,
) {
  final pinnedIds = pinned.map((i) => i.id).toSet();
  return sortFleetIssuesByPriority(
    openIssues.where((i) => !pinnedIds.contains(i.id)).toList(),
  );
}