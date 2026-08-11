import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { objectStorage } from '../services/object-storage';
import { verifyMediaAccessToken } from '../services/media-access';

export async function readMediaAsset(req: Request, res: Response) {
  const token = typeof req.query.token === 'string' ? req.query.token : '';
  let assetId: string;
  try {
    const claims = verifyMediaAccessToken(token);
    assetId = claims.assetId;
  } catch {
    return res.status(401).json({ message: 'Der Medienzugriff ist abgelaufen oder ungültig.' });
  }

  if (assetId !== req.params.id) {
    return res.status(403).json({ message: 'Der Medienzugriff gilt nicht für diese Datei.' });
  }

  const asset = await prisma.fileAsset.findFirst({
    where: { id: assetId, deletedAt: null },
    select: { pathname: true, contentType: true, size: true },
  });
  if (!asset) {
    return res.status(404).json({ message: 'Die Datei wurde nicht gefunden.' });
  }

  const stored = await objectStorage.readPrivate(asset.pathname);
  if (!stored) {
    return res.status(404).json({ message: 'Die Datei ist im Speicher nicht verfügbar.' });
  }

  res.set({
    'Content-Type': stored.contentType || asset.contentType,
    'Content-Length': String(stored.size || asset.size),
    'Cache-Control': 'private, no-store, max-age=0',
    ETag: stored.etag,
    'X-Content-Type-Options': 'nosniff',
  });
  return res.status(200).send(stored.data);
}
