export type RuntimeEnvironment =
  | 'production'
  | 'demo'
  | 'development'
  | 'test';

function normalizedEnvironment(value: string | undefined): RuntimeEnvironment {
  const normalized = value?.trim().toLowerCase();
  if (
    normalized === 'production' ||
    normalized === 'demo' ||
    normalized === 'development' ||
    normalized === 'test'
  ) {
    return normalized;
  }
  return process.env.NODE_ENV === 'production' ? 'production' : 'development';
}

export const runtimeEnvironment = normalizedEnvironment(
  process.env.APP_ENVIRONMENT,
);

export const isDemoEnvironment = runtimeEnvironment === 'demo';
const productionDatabaseUrl = process.env.DATABASE_URL;
const demoDatabaseUrl = process.env.DEMO_DATABASE_URL?.trim();

/**
 * The demo deployment deliberately reads a separate variable. It must never
 * silently fall back to DATABASE_URL because that variable belongs to the
 * production deployment and a fallback would defeat the isolation guarantee.
 */
export function databaseUrlForRuntime() {
  if (!isDemoEnvironment) return productionDatabaseUrl;
  if (!demoDatabaseUrl) {
    throw new Error(
      'APP_ENVIRONMENT=demo requires an isolated DEMO_DATABASE_URL.',
    );
  }
  return demoDatabaseUrl;
}

/**
 * Demo data may create in-app notification records, but it must never contact
 * real push or email providers. A separate demo instance therefore cannot
 * accidentally notify productive users even when provider secrets are copied.
 */
export const externalDeliveriesAllowed = !isDemoEnvironment;
