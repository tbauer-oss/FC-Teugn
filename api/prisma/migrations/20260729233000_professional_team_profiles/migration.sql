CREATE TYPE "TeamType" AS ENUM ('COMPETITIVE', 'DEVELOPMENT', 'FESTIVAL', 'RECREATIONAL');
CREATE TYPE "TeamGender" AS ENUM ('MIXED', 'MALE', 'FEMALE');
ALTER TYPE "FileAssetKind" ADD VALUE 'TEAM_PHOTO';

ALTER TABLE "Team"
ADD COLUMN "teamType" "TeamType" NOT NULL DEFAULT 'COMPETITIVE',
ADD COLUMN "gender" "TeamGender" NOT NULL DEFAULT 'MIXED',
ADD COLUMN "birthYears" INTEGER[] NOT NULL DEFAULT ARRAY[]::INTEGER[],
ADD COLUMN "description" TEXT,
ADD COLUMN "trainingLocation" TEXT,
ADD COLUMN "trainingTimes" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
ADD COLUMN "homeVenue" TEXT,
ADD COLUMN "bfvTeamId" TEXT,
ADD COLUMN "dfbnetTeamId" TEXT,
ADD COLUMN "bfvTeamUrl" TEXT,
ADD COLUMN "photoAssetId" TEXT;

ALTER TABLE "FileAsset" ADD COLUMN "ownerTeamId" TEXT;

CREATE UNIQUE INDEX "Team_photoAssetId_key" ON "Team"("photoAssetId");
CREATE INDEX "FileAsset_ownerTeamId_kind_deletedAt_idx"
ON "FileAsset"("ownerTeamId", "kind", "deletedAt");

ALTER TABLE "Team"
ADD CONSTRAINT "Team_photoAssetId_fkey"
FOREIGN KEY ("photoAssetId") REFERENCES "FileAsset"("id")
ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "FileAsset"
ADD CONSTRAINT "FileAsset_ownerTeamId_fkey"
FOREIGN KEY ("ownerTeamId") REFERENCES "Team"("id")
ON DELETE SET NULL ON UPDATE CASCADE;
