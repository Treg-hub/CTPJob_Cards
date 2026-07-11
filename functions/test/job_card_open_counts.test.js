const test = require('node:test');
const assert = require('node:assert/strict');
const {
  isOpenJobStatus,
  isCriticalPriority,
  deltaForTransition,
  countingFieldsChanged,
} = require('../job_card_open_counts');

test('isOpenJobStatus accepts mobile and Pulse variants', () => {
  assert.equal(isOpenJobStatus('open'), true);
  assert.equal(isOpenJobStatus('In Progress'), true);
  assert.equal(isOpenJobStatus('monitor'), true);
  assert.equal(isOpenJobStatus('closed'), false);
});

test('deltaForTransition on close decrements active', () => {
  const d = deltaForTransition(
    { status: 'open', priority: 4 },
    { status: 'closed', priority: 4 },
  );
  assert.equal(d.activeDelta, -1);
  assert.equal(d.criticalDelta, -1);
});

test('countingFieldsChanged ignores comment-only updates', () => {
  assert.equal(
    countingFieldsChanged(
      { status: 'open', priority: 3, comments: 'a' },
      { status: 'open', priority: 3, comments: 'b' },
    ),
    false,
  );
});

test('soft-delete of open job decrements active', () => {
  const d = deltaForTransition(
    { status: 'open', priority: 4, is_deleted: false },
    { status: 'open', priority: 4, is_deleted: true },
  );
  assert.equal(d.activeDelta, -1);
  assert.equal(d.criticalDelta, -1);
});

test('missing is_deleted still counts as open', () => {
  const d = deltaForTransition(null, { status: 'open', priority: 3 });
  assert.equal(d.activeDelta, 1);
  assert.equal(d.criticalDelta, 0);
});