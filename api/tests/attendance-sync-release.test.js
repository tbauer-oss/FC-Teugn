const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

function source(relativePath) {
  return fs.readFileSync(path.join(__dirname, '..', relativePath), 'utf8');
}

test('attendance mutation returns the fully refreshed event snapshot', () => {
  const events = source('src/controllers/events.controller.ts');
  assert.match(
    events,
    /export async function setAttendance[\s\S]*include:\s*eventInclude[\s\S]*\.\.\.attendance[\s\S]*event:\s*await serializeEvent\(refreshedEvent, user\)/,
  );
});

test('Flutter confirms the changed response without blocking on full calendar reloads', () => {
  const repository = source('../fc_teugn_app/lib/core/data_repository.dart');
  const family = source('../fc_teugn_app/lib/features/shared/family_responses.dart');
  const calendar = source('../fc_teugn_app/lib/features/calendar/calendar_page.dart');

  assert.match(repository, /Future<EventModel> setAttendance/);
  assert.match(repository, /EventModel\.fromJson\(payload\['event'\]/);
  assert.match(family, /invalidate\(personalResponsesProvider\)/);
  assert.match(family, /invalidate\(eventsProvider\)/);
  assert.match(family, /personalResponsesProvider\.future/);
  assert.doesNotMatch(family, /eventsProvider\.future/);

  assert.match(calendar, /invalidate\(personalResponsesProvider\)/);
  assert.match(calendar, /invalidate\(eventsProvider\)/);
  assert.match(calendar, /personalResponsesProvider\.future/);
  assert.match(calendar, /eventsProvider\.future/);
});
