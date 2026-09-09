import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const template = readFileSync(new URL('../fc_teugn_app/web/flutter_bootstrap.js', import.meta.url), 'utf8');

function boot(id, cachedScripts, deployedBuild) {
  let loadedBuild;
  let requestedUrl;
  let workerVersion;
  const flutter = {
    buildConfig: {builds: [{mainJsPath: 'main.dart.js'}, {}]},
    loader: {load: ({serviceWorkerSettings}) => {
      requestedUrl = new URL(flutter.buildConfig.builds[0].mainJsPath, 'https://app.example/').href;
      loadedBuild = cachedScripts.get(requestedUrl) ?? deployedBuild;
      cachedScripts.set(requestedUrl, loadedBuild);
      workerVersion = serviceWorkerSettings.serviceWorkerVersion;
    }},
  };
  vm.runInNewContext(template
    .replace('{{flutter_js}}', '')
    .replace('{{flutter_build_config}}', '')
    .replace('{{flutter_service_worker_version}}', JSON.stringify(id)), {
      _flutter: flutter, URL, document: {baseURI: 'https://app.example/'},
    });
  return {loadedBuild, requestedUrl, workerVersion};
}

test('a cached old app cannot reappear after updating or reloading', () => {
  const cache = new Map([['https://app.example/main.dart.js', 194]]);
  const first = boot('release-195', cache, 195);
  assert.equal(first.loadedBuild, 195);
  assert.equal(new URL(first.requestedUrl).searchParams.get('build'), 'release-195');
  assert.equal(boot('release-195', cache, 195).loadedBuild, 195);
  assert.equal(boot('release-196', cache, 196).loadedBuild, 196);
  assert.equal(boot('release-196', cache, 196).loadedBuild, 196);
});

test('existing offline workers still receive Flutter migration updates', () => {
  assert.equal(boot('release-196', new Map(), 196).workerVersion, 'release-196');
});
