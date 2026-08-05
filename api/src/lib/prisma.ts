import { PrismaClient } from '@prisma/client';

type PrismaGlobal = typeof globalThis & {
  fcTeugnPrisma?: PrismaClient;
};

/**
 * Prisma opens a connection pool for every serverless function instance. The
 * default pool size is intended for long-running servers and can exhaust a
 * small production database during a burst of parallel app requests.
 *
 * Keep explicitly configured limits untouched. On Vercel, otherwise use one
 * connection per warm function instance and fail a pool wait before the HTTP
 * request itself reaches its deadline.
 */
export function serverlessDatabaseUrl(
  value: string | undefined,
  serverless = process.env.VERCEL === '1',
) {
  if (!value || !serverless) return value;
  try {
    const url = new URL(value);
    if (url.protocol !== 'postgres:' && url.protocol !== 'postgresql:') {
      return value;
    }
    if (!url.searchParams.has('connection_limit')) {
      url.searchParams.set('connection_limit', '1');
    }
    if (!url.searchParams.has('pool_timeout')) {
      url.searchParams.set('pool_timeout', '10');
    }
    if (!url.searchParams.has('connect_timeout')) {
      url.searchParams.set('connect_timeout', '10');
    }
    return url.toString();
  } catch {
    // Prisma will surface the original configuration error with its normal,
    // more actionable diagnostics during startup.
    return value;
  }
}

const prismaGlobal = globalThis as PrismaGlobal;
const datasourceUrl = serverlessDatabaseUrl(process.env.DATABASE_URL);

export const prisma = prismaGlobal.fcTeugnPrisma ?? new PrismaClient({
  ...(datasourceUrl ? { datasourceUrl } : {}),
});

// Reuse the client across warm Vercel invocations and development reloads.
prismaGlobal.fcTeugnPrisma = prisma;
