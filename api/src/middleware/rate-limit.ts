import { NextFunction, Request, Response } from 'express';
import { createHash } from 'crypto';

interface RateBucket {
  count: number;
  resetAt: number;
}
const buckets = new Map<string, RateBucket>();

function credentialFingerprint(req: Request) {
  const email = req.body?.email;
  const candidate = typeof email === 'string' && email.trim().length > 0
    ? email.trim().toLowerCase()
    : [req.body?.requestId, req.body?.token]
      .find((value) => typeof value === 'string' && value.trim().length > 0)
      ?.trim();
  if (!candidate) return null;
  return createHash('sha256')
    .update(candidate)
    .digest('hex')
    .slice(0, 24);
}

function consumeBucket(key: string, maximum: number, now: number, windowMs: number) {
  let bucket = buckets.get(key);
  if (!bucket || bucket.resetAt <= now) {
    bucket = { count: 0, resetAt: now + windowMs };
    buckets.set(key, bucket);
  }
  bucket.count += 1;
  return {
    blocked: bucket.count > maximum,
    remaining: Math.max(0, maximum - bucket.count),
    resetAt: bucket.resetAt,
  };
}

export function authRateLimit(req: Request, res: Response, next: NextFunction) {
  if (
    req.method !== 'POST' ||
    ![
      '/login',
      '/register',
      '/password-reset/request',
      '/password-reset/exchange',
      '/password-reset/confirm',
    ].includes(req.path)
  ) {
    return next();
  }
  const now = Date.now();
  const windowMs = 15 * 60 * 1000;
  const maxRequests = req.path === '/login'
    ? 20
    : req.path === '/password-reset/request'
      ? 5
      : 8;
  const fingerprint = credentialFingerprint(req);
  const credential = consumeBucket(
    `credential:${req.path}:${fingerprint ?? req.ip}`,
    maxRequests,
    now,
    windowMs,
  );
  // Mobilfunk-Carrier und Vereins-WLANs teilen oft eine öffentliche IP.
  // Das großzügigere Netzlimit hält automatisierte Streuversuche auf, ohne
  // verschiedene Mitglieder schon nach wenigen Anmeldungen auszusperren.
  const network = consumeBucket(
    `network:${req.path}:${req.ip}`,
    maxRequests * 10,
    now,
    windowMs,
  );
  const remaining = credential.remaining;
  const resetAt = Math.max(credential.resetAt, network.resetAt);
  res.setHeader('RateLimit-Limit', maxRequests);
  res.setHeader('RateLimit-Remaining', remaining);
  res.setHeader('RateLimit-Reset', Math.ceil(resetAt / 1000));
  if (credential.blocked || network.blocked) {
    const retryAfterSeconds = Math.max(1, Math.ceil((resetAt - now) / 1000));
    res.setHeader('Retry-After', retryAfterSeconds);
    return res.status(429).json({
      code: 'AUTH_RATE_LIMITED',
      retryAfterSeconds,
      message:
        `Zu viele Versuche. Bitte in ${Math.ceil(retryAfterSeconds / 60)} Minute(n) erneut versuchen.`,
    });
  }
  if (buckets.size > 5000) {
    for (const [bucketKey, value] of buckets) {
      if (value.resetAt <= now) buckets.delete(bucketKey);
    }
  }
  return next();
}

export function sensitiveActionRateLimit(
  req: Request,
  res: Response,
  next: NextFunction,
) {
  const now = Date.now();
  const windowMs = 15 * 60 * 1000;
  const maxRequests = 10;
  const key = `${req.ip}:${req.user?.id ?? 'anonymous'}:sensitive:${req.path}`;
  let bucket = buckets.get(key);
  if (!bucket || bucket.resetAt <= now) {
    bucket = { count: 0, resetAt: now + windowMs };
    buckets.set(key, bucket);
  }
  bucket.count += 1;
  res.setHeader('RateLimit-Limit', maxRequests);
  res.setHeader('RateLimit-Remaining', Math.max(0, maxRequests - bucket.count));
  res.setHeader('RateLimit-Reset', Math.ceil(bucket.resetAt / 1000));
  if (bucket.count > maxRequests) {
    res.setHeader('Retry-After', Math.ceil((bucket.resetAt - now) / 1000));
    return res.status(429).json({
      message: 'Zu viele Bestätigungsversuche. Bitte später erneut versuchen.',
    });
  }
  return next();
}
