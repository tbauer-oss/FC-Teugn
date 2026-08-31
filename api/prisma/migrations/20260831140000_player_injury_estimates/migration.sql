ALTER TABLE "Player"
ADD COLUMN "injurySeverity" TEXT,
ADD COLUMN "injuryStartDate" TIMESTAMP(3),
ADD COLUMN "estimatedRecoveryMinDays" INTEGER,
ADD COLUMN "estimatedRecoveryMaxDays" INTEGER,
ADD COLUMN "estimatedReturnFrom" TIMESTAMP(3),
ADD COLUMN "estimatedReturnTo" TIMESTAMP(3),
ADD COLUMN "manualReturnFrom" TIMESTAMP(3),
ADD COLUMN "manualReturnTo" TIMESTAMP(3),
ADD COLUMN "recoveryEstimateOverridden" BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE "PlayerInjuryRecord" (
  "id" TEXT NOT NULL,
  "playerId" TEXT NOT NULL,
  "injuryType" TEXT,
  "injuryDetails" TEXT,
  "injurySeverity" TEXT,
  "startDate" TIMESTAMP(3),
  "estimatedRecoveryMinDays" INTEGER,
  "estimatedRecoveryMaxDays" INTEGER,
  "estimatedReturnFrom" TIMESTAMP(3),
  "estimatedReturnTo" TIMESTAMP(3),
  "manualReturnFrom" TIMESTAMP(3),
  "manualReturnTo" TIMESTAMP(3),
  "recoveryEstimateOverridden" BOOLEAN NOT NULL DEFAULT false,
  "endedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "PlayerInjuryRecord_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "PlayerInjuryRecord_playerId_endedAt_idx"
ON "PlayerInjuryRecord"("playerId", "endedAt");

CREATE INDEX "PlayerInjuryRecord_playerId_createdAt_idx"
ON "PlayerInjuryRecord"("playerId", "createdAt");

ALTER TABLE "PlayerInjuryRecord"
ADD CONSTRAINT "PlayerInjuryRecord_playerId_fkey"
FOREIGN KEY ("playerId") REFERENCES "Player"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

INSERT INTO "PlayerInjuryRecord" (
  "id",
  "playerId",
  "injuryType",
  "injuryDetails",
  "injurySeverity",
  "startDate",
  "estimatedRecoveryMinDays",
  "estimatedRecoveryMaxDays",
  "estimatedReturnFrom",
  "estimatedReturnTo",
  "manualReturnFrom",
  "manualReturnTo",
  "recoveryEstimateOverridden",
  "createdAt",
  "updatedAt"
)
SELECT
  'injury_' || "id",
  "id",
  "injuryType",
  "injuryDetails",
  "injurySeverity",
  "injuryStartDate",
  "estimatedRecoveryMinDays",
  "estimatedRecoveryMaxDays",
  "estimatedReturnFrom",
  "estimatedReturnTo",
  "manualReturnFrom",
  "manualReturnTo",
  "recoveryEstimateOverridden",
  "updatedAt",
  "updatedAt"
FROM "Player"
WHERE "status" = 'INJURED'
  AND ("injuryType" IS NOT NULL OR "injuryDetails" IS NOT NULL);
