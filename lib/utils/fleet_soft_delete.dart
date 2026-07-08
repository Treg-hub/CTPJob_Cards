/// Pulse admin soft-delete flag on fleet_issues / fleet_work_records.
bool parseFleetDeleted(Map<String, dynamic>? data) =>
    data != null && data['is_deleted'] == true;