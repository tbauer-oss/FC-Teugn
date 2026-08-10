-- Vereine werden einmal zentral je FC-Teugn-Organisation geführt. Die
-- jugendbezogenen Mannschaften bleiben in "Opponent" und verweisen darauf.
CREATE TABLE "OpponentClub" (
    "id" TEXT NOT NULL,
    "organizationClubId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "shortName" TEXT,
    "normalizedName" TEXT NOT NULL,
    "venue" TEXT,
    "address" TEXT,
    "logoAssetId" TEXT,
    "createdById" TEXT NOT NULL,
    "archivedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "OpponentClub_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "Opponent" ADD COLUMN "opponentClubId" TEXT;

-- Bestehende Gegner gleicher Vereine werden jugendübergreifend zu genau
-- einem Verein zusammengeführt. Wappen, Spielstätte und Adresse bleiben
-- erhalten; bevorzugt wird der zuletzt gepflegte Datensatz.
INSERT INTO "OpponentClub" (
  "id", "organizationClubId", "name", "shortName", "normalizedName",
  "venue", "address", "logoAssetId", "createdById", "createdAt", "updatedAt"
)
SELECT DISTINCT ON (
  s."clubId",
  lower(trim(regexp_replace(translate(o."clubName", 'ÄÖÜäöü', 'AOUaou'), '[^a-zA-Z0-9]+', ' ', 'g')))
)
  'opclub_' || md5(
    s."clubId" || ':' ||
    lower(trim(regexp_replace(translate(o."clubName", 'ÄÖÜäöü', 'AOUaou'), '[^a-zA-Z0-9]+', ' ', 'g')))
  ),
  s."clubId",
  trim(o."clubName"),
  o."shortName",
  lower(trim(regexp_replace(translate(o."clubName", 'ÄÖÜäöü', 'AOUaou'), '[^a-zA-Z0-9]+', ' ', 'g'))),
  o."venue",
  o."address",
  o."logoAssetId",
  o."createdById",
  o."createdAt",
  o."updatedAt"
FROM "Opponent" o
JOIN "AgeGroup" a ON a."id" = o."ageGroupId"
JOIN "Season" s ON s."id" = a."seasonId"
ORDER BY s."clubId",
  lower(trim(regexp_replace(translate(o."clubName", 'ÄÖÜäöü', 'AOUaou'), '[^a-zA-Z0-9]+', ' ', 'g'))),
  (o."logoAssetId" IS NOT NULL) DESC, o."updatedAt" DESC;

UPDATE "Opponent" o
SET "opponentClubId" = c."id"
FROM "AgeGroup" a
JOIN "Season" s ON s."id" = a."seasonId"
JOIN "OpponentClub" c ON c."organizationClubId" = s."clubId"
WHERE o."ageGroupId" = a."id"
  AND c."normalizedName" =
    lower(trim(regexp_replace(translate(o."clubName", 'ÄÖÜäöü', 'AOUaou'), '[^a-zA-Z0-9]+', ' ', 'g')));

ALTER TABLE "Opponent" ALTER COLUMN "opponentClubId" SET NOT NULL;

CREATE UNIQUE INDEX "OpponentClub_logoAssetId_key" ON "OpponentClub"("logoAssetId");
CREATE UNIQUE INDEX "OpponentClub_organizationClubId_normalizedName_key"
  ON "OpponentClub"("organizationClubId", "normalizedName");
CREATE INDEX "OpponentClub_organizationClubId_archivedAt_name_idx"
  ON "OpponentClub"("organizationClubId", "archivedAt", "name");
CREATE UNIQUE INDEX "Opponent_ageGroupId_opponentClubId_teamDesignation_key"
  ON "Opponent"("ageGroupId", "opponentClubId", "teamDesignation");
CREATE INDEX "Opponent_opponentClubId_ageGroupId_archivedAt_idx"
  ON "Opponent"("opponentClubId", "ageGroupId", "archivedAt");

ALTER TABLE "OpponentClub" ADD CONSTRAINT "OpponentClub_organizationClubId_fkey"
  FOREIGN KEY ("organizationClubId") REFERENCES "Club"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "OpponentClub" ADD CONSTRAINT "OpponentClub_logoAssetId_fkey"
  FOREIGN KEY ("logoAssetId") REFERENCES "FileAsset"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "OpponentClub" ADD CONSTRAINT "OpponentClub_createdById_fkey"
  FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "Opponent" ADD CONSTRAINT "Opponent_opponentClubId_fkey"
  FOREIGN KEY ("opponentClubId") REFERENCES "OpponentClub"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
