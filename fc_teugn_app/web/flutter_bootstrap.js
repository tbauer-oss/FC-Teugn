{{flutter_js}}
{{flutter_build_config}}

// Flutter generates a new identifier for each web build. The bootstrap is
// fetched fresh; its entry point must not reuse a previous build's HTTP cache.
const webBuildId = {{flutter_service_worker_version}};
for (const build of _flutter.buildConfig.builds) {
  for (const key of ['mainJsPath', 'mainWasmPath', 'jsSupportRuntimePath']) {
    if (build[key]) {
      const url = new URL(build[key], document.baseURI);
      url.searchParams.set('build', webBuildId);
      build[key] = url.href;
    }
  }
}

// Retain Flutter's migration of existing legacy offline workers. Push has its
// own registration and scope and is not part of this migration.
_flutter.loader.load({
  serviceWorkerSettings: {serviceWorkerVersion: webBuildId}
});
