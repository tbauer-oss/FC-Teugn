const assert = require('node:assert/strict');
const test = require('node:test');

function loadRuntimeEnvironment(environment, values = {}) {
  const previous = {
    APP_ENVIRONMENT: process.env.APP_ENVIRONMENT,
    NODE_ENV: process.env.NODE_ENV,
    DATABASE_URL: process.env.DATABASE_URL,
    DEMO_DATABASE_URL: process.env.DEMO_DATABASE_URL,
  };
  process.env.APP_ENVIRONMENT = environment;
  process.env.NODE_ENV = values.NODE_ENV ?? 'production';
  if (values.DATABASE_URL == null) delete process.env.DATABASE_URL;
  else process.env.DATABASE_URL = values.DATABASE_URL;
  if (values.DEMO_DATABASE_URL == null) delete process.env.DEMO_DATABASE_URL;
  else process.env.DEMO_DATABASE_URL = values.DEMO_DATABASE_URL;
  const path = require.resolve('../dist/src/lib/runtime-environment');
  delete require.cache[path];
  try {
    return require(path);
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

test('production uses only the production database URL', () => {
  const runtime = loadRuntimeEnvironment('production', {
    DATABASE_URL: 'postgresql://production.example/app',
    DEMO_DATABASE_URL: 'postgresql://demo.example/app',
  });
  assert.equal(runtime.runtimeEnvironment, 'production');
  assert.equal(runtime.externalDeliveriesAllowed, true);
  assert.equal(
    runtime.databaseUrlForRuntime(),
    'postgresql://production.example/app',
  );
});

test('demo uses only the isolated demo database and disables deliveries', () => {
  const runtime = loadRuntimeEnvironment('demo', {
    DATABASE_URL: 'postgresql://production.example/app',
    DEMO_DATABASE_URL: 'postgresql://demo.example/app',
  });
  assert.equal(runtime.runtimeEnvironment, 'demo');
  assert.equal(runtime.externalDeliveriesAllowed, false);
  assert.equal(
    runtime.databaseUrlForRuntime(),
    'postgresql://demo.example/app',
  );
});

test('demo fails closed without its dedicated database variable', () => {
  const runtime = loadRuntimeEnvironment('demo', {
    DATABASE_URL: 'postgresql://production.example/app',
  });
  assert.throws(
    () => runtime.databaseUrlForRuntime(),
    /requires an isolated DEMO_DATABASE_URL/,
  );
});
