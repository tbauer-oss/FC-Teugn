-- Preserve team membership per season before changing primary team pointers.
CREATE TYPE "SeasonTransitionStatus" AS ENUM ('PREVIEWED', 'APPLIED', 'FAILED');

ALTER TABLE "RuleProfile"
ADD COLUMN "createdById" TEXT,
ADD COLUMN "approvedById" TEXT;

CREATE TABLE "PlayerSeasonAssignment" (
  "id" TEXT NOT NULL,
  "playerId" TEXT NOT NULL,
  "seasonId" TEXT NOT NULL,
  "teamId" TEXT NOT NULL,
  "status" "PlayerStatus" NOT NULL DEFAULT 'ACTIVE',
  "assignedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "endedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "PlayerSeasonAssignment_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "SeasonTransition" (
  "id" TEXT NOT NULL,
  "clubId" TEXT NOT NULL,
  "sourceSeasonId" TEXT NOT NULL,
  "targetSeasonId" TEXT,
  "actorId" TEXT NOT NULL,
  "status" "SeasonTransitionStatus" NOT NULL DEFAULT 'PREVIEWED',
  "idempotencyKey" TEXT NOT NULL,
  "plan" JSONB NOT NULL,
  "preview" JSONB NOT NULL,
  "result" JSONB,
  "appliedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "SeasonTransition_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "PlayerSeasonAssignment_playerId_seasonId_key"
ON "PlayerSeasonAssignment"("playerId", "seasonId");
CREATE INDEX "PlayerSeasonAssignment_teamId_status_idx"
ON "PlayerSeasonAssignment"("teamId", "status");
CREATE UNIQUE INDEX "SeasonTransition_idempotencyKey_key"
ON "SeasonTransition"("idempotencyKey");
CREATE INDEX "SeasonTransition_clubId_createdAt_idx"
ON "SeasonTransition"("clubId", "createdAt");
CREATE INDEX "SeasonTransition_sourceSeasonId_status_idx"
ON "SeasonTransition"("sourceSeasonId", "status");

ALTER TABLE "PlayerSeasonAssignment"
ADD CONSTRAINT "PlayerSeasonAssignment_playerId_fkey" FOREIGN KEY ("playerId") REFERENCES "Player"("id") ON DELETE CASCADE ON UPDATE CASCADE,
ADD CONSTRAINT "PlayerSeasonAssignment_seasonId_fkey" FOREIGN KEY ("seasonId") REFERENCES "Season"("id") ON DELETE CASCADE ON UPDATE CASCADE,
ADD CONSTRAINT "PlayerSeasonAssignment_teamId_fkey" FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "SeasonTransition"
ADD CONSTRAINT "SeasonTransition_clubId_fkey" FOREIGN KEY ("clubId") REFERENCES "Club"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
ADD CONSTRAINT "SeasonTransition_sourceSeasonId_fkey" FOREIGN KEY ("sourceSeasonId") REFERENCES "Season"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
ADD CONSTRAINT "SeasonTransition_targetSeasonId_fkey" FOREIGN KEY ("targetSeasonId") REFERENCES "Season"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
ADD CONSTRAINT "SeasonTransition_actorId_fkey" FOREIGN KEY ("actorId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "RuleProfile"
ADD CONSTRAINT "RuleProfile_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE,
ADD CONSTRAINT "RuleProfile_approvedById_fkey" FOREIGN KEY ("approvedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Backfill the current season/team as the first historical assignment.
INSERT INTO "PlayerSeasonAssignment" ("id", "playerId", "seasonId", "teamId", "status", "assignedAt", "createdAt", "updatedAt")
SELECT
  'psa_' || md5(p."id" || s."id"),
  p."id",
  s."id",
  p."teamId",
  p."status",
  COALESCE(p."joinedAt", p."createdAt"),
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM "Player" p
JOIN "Team" t ON t."id" = p."teamId"
JOIN "AgeGroup" ag ON ag."id" = t."ageGroupId"
JOIN "Season" s ON s."id" = ag."seasonId"
ON CONFLICT ("playerId", "seasonId") DO NOTHING;
