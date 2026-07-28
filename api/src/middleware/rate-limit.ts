import { NextFunction, Request, Response } from 'express';

interface RateBucket {
  count: number;
  resetAt: number;
}
const buckets = new Map<string, RateBucket>();

export function authRateLimit(req: Request, res: Response, next: NextFunction) {
  if (req.method !== 'POST' || !['/login', '/register'].includes(req.path)) {
    return next();
  }
  const now = Date.now();
  const windowMs = 15 * 60 * 1000;
  const maxRequests = req.path === '/login' ? 20 : 8;
  const key = `${req.ip}:${req.path}`;
  let bucket = buckets.get(key);
  if (!bucket || bucket.resetAt <= now) {
    bucket = { count: 0, resetAt: now + windowMs };
    buckets.set(key, bucket);
  }
  bucket.count += 1;
  const remaining = Math.max(0, maxRequests - bucket.count);
  res.setHeader('RateLimit-Limit', maxRequests);
  res.setHeader('RateLimit-Remaining', remaining);
  res.setHeader('RateLimit-Reset', Math.ceil(bucket.resetAt / 1000));
  if (bucket.count > maxRequests) {
    res.setHeader('Retry-After', Math.ceil((bucket.resetAt - now) / 1000));
    return res.status(429).json({
      message: 'Zu viele Anfragen. Bitte später erneut versuchen.',
    });
  }
  if (buckets.size > 5000) {
    for (const [bucketKey, value] of buckets) {
      if (value.resetAt <= now) buckets.delete(bucketKey);
    }
  }
  return next();
}
