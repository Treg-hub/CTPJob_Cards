/// Soft-delete flag on [job_cards] (admin only). Missing field = not deleted.
bool parseJobCardDeleted(Map<String, dynamic>? data) =>
    data != null && data['is_deleted'] == true;
