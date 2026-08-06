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

test('Flutter refreshes family responses and calendar before confirming success', () => {
  const repository = source('../fc_teugn_app/lib/core/data_repository.dart');
  const family = source('../fc_teugn_app/lib/features/shared/family_responses.dart');
  const calendar = source('../fc_teugn_app/lib/features/calendar/calendar_page.dart');

  assert.match(repository, /Future<EventModel> setAttendance/);
  assert.match(repository, /EventModel\.fromJson\(payload\['event'\]/);
  for (const ui of [family, calendar]) {
    assert.match(ui, /invalidate\(personalResponsesProvider\)/);
    assert.match(ui, /invalidate\(eventsProvider\)/);
    assert.match(ui, /personalResponsesProvider\.future/);
    assert.match(ui, /eventsProvider\.future/);
  }
});
