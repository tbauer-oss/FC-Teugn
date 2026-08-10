const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), 'utf8');

const schema = read('prisma/schema.prisma');
const migration = read('prisma/migrations/20260807150000_bfv_team_sync/migration.sql');
const service = read('src/services/bfv-sync.service.ts');
const routes = read('src/routes/competitions.routes.ts');
const controller = read('src/controllers/bfv-sync.controller.ts');
const cron = read('src/controllers/cron.controller.ts');
const flutterTab = read('../fc_teugn_app/lib/features/matches/bfv_sync_tab.dart');
const widgetPage = read('../fc_teugn_app/web/bfv-widget.html');

test('BfV sync is stored per season-specific team', () => {
  assert.match(schema, /model BfvTeamSync[\s\S]*teamId\s+String\s+@unique/);
  assert.match(schema, /syncIntervalMinutes\s+Int\s+@default\(30\)/);
  assert.match(migration, /CREATE TABLE "BfvTeamSync"/);
});

test('BfV sync only downloads official HTTPS calendar URLs and protects local edits', () => {
  assert.match(service, /url\.protocol !== 'https:'/);
  assert.match(service, /url\.hostname\.toLowerCase\(\) !== 'service\.bfv\.de'/);
  assert.match(service, /locallyChanged/);
  assert.match(service, /SUCCESS_WITH_CONFLICTS/);
});

test('BfV sync is permission guarded, scheduled and exposed in the app', () => {
  assert.match(routes, /Permission\.MANAGE_IMPORTS[\s\S]*getBfvSyncConfig/);
  assert.match(routes, /Permission\.MANAGE_IMPORTS[\s\S]*runBfvSync/);
  assert.match(cron, /processDueBfvSyncs/);
  assert.match(flutterTab, /Jetzt synchronisieren/);
  assert.match(flutterTab, /Tabelle & Ligaspiele/);
  assert.match(widgetPage, /zeigeMannschaftKomplett/);
  assert.match(widgetPage, /fcTeugnBfvWidgetConsent/);
  assert.match(widgetPage, /colorResults:\s*'#11150f'/);
  assert.doesNotMatch(widgetPage, /colorResults:\s*'#fff4a8'/);
});

test('system administrators can save all widget team identifiers centrally', () => {
  assert.match(
    routes,
    /bfv-widget-teams[\s\S]*Role\.SUPER_ADMIN[\s\S]*saveBfvWidgetTeamIds/,
  );
  assert.match(controller, /BFV_WIDGET_TEAM_IDS_UPDATED/);
  assert.match(controller, /prisma\.\$transaction/);
  assert.match(flutterTab, /Alle Mannschaftskennungen zentral verwalten/);
  assert.match(flutterTab, /Alle Kennungen speichern/);
});
