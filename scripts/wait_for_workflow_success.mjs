import { pathToFileURL } from 'node:url';

export async function waitForWorkflow({ repository, workflow, sha, token, fetcher = fetch,
  sleep = ms => new Promise(resolve => setTimeout(resolve, ms)), now = Date.now,
  timeoutMs = 900000, log = console.log }) {
  if (!repository || !workflow || !/^[a-f0-9]{40}$/i.test(sha ?? '') || !token) {
    throw new Error('Repository, Workflow, vollständiger Commit und GitHub-Zugang sind erforderlich.');
  }
  const deadline = now() + timeoutMs;
  let lastState;
  while (now() < deadline) {
    const response = await fetcher(`https://api.github.com/repos/${repository}/actions/workflows/${encodeURIComponent(workflow)}/runs?head_sha=${sha}&per_page=30`, {
      headers: { authorization: `Bearer ${token}`, accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' },
      signal: AbortSignal.timeout(20000),
    });
    if (!response.ok) throw new Error(`Workflowstatus nicht abrufbar (HTTP ${response.status}). Keine Veröffentlichung.`);
    const runs = (await response.json()).workflow_runs ?? [];
    const run = runs.filter(r => r.head_sha === sha && ['push', 'workflow_dispatch'].includes(r.event))
      .sort((a, b) => b.run_number - a.run_number)[0];
    const state = `${run?.id ?? 'ausstehend'}:${run?.status ?? 'ausstehend'}:${run?.conclusion ?? ''}`;
    if (state !== lastState) {
      log(`${workflow}: ${run?.status ?? 'Start ausstehend'}${run?.conclusion ? ` (${run.conclusion})` : ''} für ${sha.slice(0, 12)}`);
      lastState = state;
    }
    if (run?.status === 'completed') {
      if (run.conclusion !== 'success') throw new Error(`${workflow} ist ${run.conclusion}. Keine Veröffentlichung.`);
      return { runId: run.id, sha };
    }
    await sleep(15000);
  }
  throw new Error(`${workflow} wurde innerhalb des Zeitlimits nicht erfolgreich abgeschlossen. Keine Veröffentlichung.`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  waitForWorkflow({ repository: process.env.GITHUB_REPOSITORY, workflow: process.argv[2], sha: process.argv[3],
    token: process.env.GH_TOKEN ?? process.env.GITHUB_TOKEN }).catch(error => {
    console.error(error.message); process.exitCode = 1;
  });
}
