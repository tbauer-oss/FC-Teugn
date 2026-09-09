ALTER TABLE "FileAsset" ADD COLUMN "storageDeletedAt" TIMESTAMP(3);
CREATE INDEX "FileAsset_deletedAt_storageDeletedAt_idx"
  ON "FileAsset"("deletedAt", "storageDeletedAt");
