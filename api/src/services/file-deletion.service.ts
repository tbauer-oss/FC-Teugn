import { prisma } from '../lib/prisma';
import { objectStorage } from './object-storage';

/** Soft-deleted metadata is the durable retry queue if Google was unavailable. */
export async function retryFileDeletions(now = new Date()) {
  const assets = await prisma.fileAsset.findMany({
    where: { deletedAt: { not: null }, storageDeletedAt: null },
    select: { id: true, pathname: true },
    orderBy: { deletedAt: 'asc' },
    take: 100,
  });
  let removed = 0;
  for (const asset of assets) {
    try {
      await objectStorage.delete(asset.pathname);
      await prisma.fileAsset.updateMany({
        where: { id: asset.id, deletedAt: { not: null }, pathname: asset.pathname },
        data: { storageDeletedAt: now },
      });
      removed++;
    } catch {
      // Keep the tombstone pending; do not expose private object names in logs.
    }
  }
  return { removed, pending: assets.length - removed };
}
