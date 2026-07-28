CREATE TYPE "FileAssetKind" AS ENUM ('PLAYER_PHOTO', 'PLAYER_DOCUMENT');
CREATE TYPE "PlayerDocumentType" AS ENUM (
  'PHOTO_CONSENT',
  'PRIVACY_CONSENT',
  'PARTICIPATION_PERMISSION',
  'SWIMMING_PERMISSION',
  'DECLARATION',
  'TEAM_DOCUMENT',
  'OTHER'
);

ALTER TABLE "Player" ADD COLUMN "photoAssetId" TEXT;

CREATE TABLE "FileAsset" (
  "id" TEXT NOT NULL,
  "kind" "FileAssetKind" NOT NULL,
  "pathname" TEXT NOT NULL,
  "storageUrl" TEXT NOT NULL,
  "originalName" TEXT NOT NULL,
  "contentType" TEXT NOT NULL,
  "size" INTEGER NOT NULL,
  "checksum" TEXT NOT NULL,
  "isPrivate" BOOLEAN NOT NULL DEFAULT true,
  "uploadedById" TEXT NOT NULL,
  "ownerPlayerId" TEXT,
  "deletedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "FileAsset_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "PlayerDocument" (
  "id" TEXT NOT NULL,
  "playerId" TEXT NOT NULL,
  "fileAssetId" TEXT NOT NULL,
  "type" "PlayerDocumentType" NOT NULL,
  "title" TEXT NOT NULL,
  "version" INTEGER NOT NULL DEFAULT 1,
  "status" "ConsentStatus" NOT NULL DEFAULT 'PENDING',
  "validFrom" TIMESTAMP(3),
  "validUntil" TIMESTAMP(3),
  "grantedBy" TEXT,
  "grantedAt" TIMESTAMP(3),
  "note" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "PlayerDocument_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "Player_photoAssetId_key" ON "Player"("photoAssetId");
CREATE UNIQUE INDEX "FileAsset_pathname_key" ON "FileAsset"("pathname");
CREATE INDEX "FileAsset_ownerPlayerId_kind_deletedAt_idx" ON "FileAsset"("ownerPlayerId", "kind", "deletedAt");
CREATE INDEX "FileAsset_uploadedById_createdAt_idx" ON "FileAsset"("uploadedById", "createdAt");
CREATE UNIQUE INDEX "PlayerDocument_fileAssetId_key" ON "PlayerDocument"("fileAssetId");
CREATE UNIQUE INDEX "PlayerDocument_playerId_type_version_key" ON "PlayerDocument"("playerId", "type", "version");
CREATE INDEX "PlayerDocument_playerId_status_validUntil_idx" ON "PlayerDocument"("playerId", "status", "validUntil");

ALTER TABLE "Player"
ADD CONSTRAINT "Player_photoAssetId_fkey" FOREIGN KEY ("photoAssetId") REFERENCES "FileAsset"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "FileAsset"
ADD CONSTRAINT "FileAsset_uploadedById_fkey" FOREIGN KEY ("uploadedById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
ADD CONSTRAINT "FileAsset_ownerPlayerId_fkey" FOREIGN KEY ("ownerPlayerId") REFERENCES "Player"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "PlayerDocument"
ADD CONSTRAINT "PlayerDocument_playerId_fkey" FOREIGN KEY ("playerId") REFERENCES "Player"("id") ON DELETE CASCADE ON UPDATE CASCADE,
ADD CONSTRAINT "PlayerDocument_fileAssetId_fkey" FOREIGN KEY ("fileAssetId") REFERENCES "FileAsset"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
