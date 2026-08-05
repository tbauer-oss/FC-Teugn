import { createHash } from 'crypto';
import type { NextFunction, Request, Response } from 'express';

import { prisma } from '../lib/prisma';

const mutationMethods = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

export async function idempotencyMiddleware(
  req: Request,
  res: Response,
  next: NextFunction,
) {
  const key = req.header('x-idempotency-key')?.trim();
  if (!key || !req.user || !mutationMethods.has(req.method.toUpperCase())) {
    next();
    return;
  }
  if (key.length > 160) {
    res.status(400).json({ message: 'Ungültiger Idempotenzschlüssel.' });
    return;
  }

  const method = req.method.toUpperCase();
  const path = req.originalUrl;
  const requestHash = createHash('sha256')
    .update(JSON.stringify({ method, path, body: req.body ?? null }))
    .digest('hex');
  const existing = await prisma.idempotencyRecord.findUnique({
    where: {
      userId_idempotencyKey: {
        userId: req.user.id,
        idempotencyKey: key,
      },
    },
  });
  if (existing) {
    if (
      existing.requestHash !== requestHash ||
      existing.method !== method ||
      existing.path !== path
    ) {
      res.status(409).json({
        message: 'Der Idempotenzschlüssel wurde bereits anders verwendet.',
      });
      return;
    }
    res.status(existing.responseStatus).json(existing.responseBody);
    return;
  }

  const originalJson = res.json.bind(res);
  res.json = ((body: unknown) => {
    const status = res.statusCode;
    // A temporary server failure must never be replayed from the idempotency
    // cache for seven days. A later retry needs a fresh chance to succeed.
    if (status === 408 || status === 429 || status >= 500) {
      return originalJson(body);
    }
    void prisma.idempotencyRecord
      .create({
        data: {
          userId: req.user!.id,
          idempotencyKey: key,
          method,
          path,
          requestHash,
          responseStatus: status,
          responseBody: (body ?? null) as never,
          expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
        },
      })
      .then(
        () => originalJson(body),
        (error) => {
          console.error('[idempotency] response cache failed', error);
          return originalJson(body);
        },
      );
    return res;
  }) as Response['json'];
  next();
}
