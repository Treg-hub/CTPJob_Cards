/**
 * Open job card counter helpers — keeps counters/job_cards_open in sync for
 * Pulse board KPIs (1-doc listener instead of N open job_cards reads).
 *
 * Must stay aligned with web/ctp-pulse open-status constants and useOpenJobCards.
 */

/** Firestore `in` query values (mobile + Pulse casing). */
const OPEN_JOB_STATUSES = [
  "open",
  "inProgress",
  "monitoring",
  "Open",
  "In Progress",
  "Monitoring",
  "monitor",
];

const COUNTER_DOC_ID = "job_cards_open";

function normalizeJobStatus(raw) {
  const s = (raw ?? "").toString().trim();
  if (!s) return "open";
  const lower = s.toLowerCase().replace(/\s+/g, "");
  switch (lower) {
    case "open":
      return "open";
    case "inprogress":
      return "inProgress";
    case "monitor":
    case "monitoring":
      return "monitoring";
    case "closed":
      return "closed";
    default:
      return s;
  }
}

function isOpenJobStatus(status) {
  const n = normalizeJobStatus(status);
  return n === "open" || n === "inProgress" || n === "monitoring";
}

function isCriticalPriority(priority) {
  return (Number(priority) || 3) >= 4;
}

/** Soft-deleted jobs never count as open (missing is_deleted = active). */
function isJobCardDeleted(data) {
  return data != null && data.is_deleted === true;
}

/** Active/critical contribution for a single job_cards doc snapshot. */
function countContribution(data) {
  if (!data || isJobCardDeleted(data) || !isOpenJobStatus(data.status)) {
    return { active: 0, critical: 0 };
  }
  return {
    active: 1,
    critical: isCriticalPriority(data.priority) ? 1 : 0,
  };
}

/** Delta when a job card transitions before → after (create/delete/update). */
function deltaForTransition(before, after) {
  const b = countContribution(before);
  const a = countContribution(after);
  return {
    activeDelta: a.active - b.active,
    criticalDelta: a.critical - b.critical,
  };
}

function countingFieldsChanged(before, after) {
  if (!before || !after) return true;
  if (isJobCardDeleted(before) !== isJobCardDeleted(after)) return true;
  const bStatus = normalizeJobStatus(before.status);
  const aStatus = normalizeJobStatus(after.status);
  if (bStatus !== aStatus) return true;
  return (Number(before.priority) || 3) !== (Number(after.priority) || 3);
}

module.exports = {
  OPEN_JOB_STATUSES,
  COUNTER_DOC_ID,
  normalizeJobStatus,
  isOpenJobStatus,
  isCriticalPriority,
  isJobCardDeleted,
  countContribution,
  deltaForTransition,
  countingFieldsChanged,
};