const test = require('node:test');
const assert = require('node:assert/strict');
const sha = 'a'.repeat(40);
const base = { repository: 'example/app', workflow: 'deploy.yml', sha, token: 'synthetic-test-token', log: () => {} };
const result = (runs, status = 200) => ({ ok: status === 200, status, json: async () => ({ workflow_runs: runs }) });
const run = { id: 7, head_sha: sha, event: 'push', run_number: 1, status: 'completed', conclusion: 'success' };
test('release gate accepts only successful deployment of the exact commit', async () => {
  const { waitForWorkflow } = await import('../../scripts/wait_for_workflow_success.mjs');
  assert.deepEqual(await waitForWorkflow({ ...base, fetcher: async () => result([run]) }), { runId: 7, sha });
});
test('release gate rejects failed deployments', async () => {
  const { waitForWorkflow } = await import('../../scripts/wait_for_workflow_success.mjs');
  await assert.rejects(waitForWorkflow({ ...base, fetcher: async () => result([{ ...run, conclusion: 'failure' }]) }), /Keine Veröffentlichung/);
});
test('another commit or a PR validation cannot unlock publication', async () => {
  const { waitForWorkflow } = await import('../../scripts/wait_for_workflow_success.mjs');
  let time = 0;
  await assert.rejects(waitForWorkflow({ ...base, now: () => time, timeoutMs: 100,
    sleep: async () => { time += 150; }, fetcher: async () => result([{ ...run, head_sha: 'b'.repeat(40) }, { ...run, event: 'pull_request' }]) }), /Zeitlimits/);
});
test('publication waits for the running deployment and fails on inaccessible status', async () => {
  const { waitForWorkflow } = await import('../../scripts/wait_for_workflow_success.mjs');
  let calls = 0;
  await waitForWorkflow({ ...base, sleep: async () => {}, fetcher: async () => result([{ ...run, status: ++calls === 1 ? 'in_progress' : 'completed' }]) });
  assert.equal(calls, 2);
  await assert.rejects(waitForWorkflow({ ...base, fetcher: async () => result([], 403) }), /HTTP 403/);
});
