ALTER TABLE "Team"
ADD COLUMN "deletedAt" TIMESTAMP(3);

ALTER TABLE "Player"
ADD COLUMN "clubId" TEXT;

UPDATE "Player" AS player
SET "clubId" = season."clubId"
FROM "Team" AS team
JOIN "AgeGroup" AS age_group ON age_group."id" = team."ageGroupId"
JOIN "Season" AS season ON season."id" = age_group."seasonId"
WHERE player."teamId" = team."id";

ALTER TABLE "Player"
ALTER COLUMN "clubId" SET NOT NULL,
ALTER COLUMN "teamId" DROP NOT NULL;

ALTER TABLE "Player"
DROP CONSTRAINT "Player_teamId_fkey";

ALTER TABLE "Player"
ADD CONSTRAINT "Player_teamId_fkey"
FOREIGN KEY ("teamId") REFERENCES "Team"("id")
ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "Player"
ADD CONSTRAINT "Player_clubId_fkey"
FOREIGN KEY ("clubId") REFERENCES "Club"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;

DROP INDEX "Team_ageGroupId_teamNumber_key";
DROP INDEX "Team_ageGroupId_isActive_idx";
DROP INDEX "Player_teamId_status_lastName_idx";

CREATE UNIQUE INDEX "Team_active_ageGroupId_teamNumber_key"
ON "Team"("ageGroupId", "teamNumber")
WHERE "deletedAt" IS NULL;

CREATE INDEX "Team_ageGroupId_isActive_deletedAt_idx"
ON "Team"("ageGroupId", "isActive", "deletedAt");

CREATE INDEX "Player_clubId_teamId_status_lastName_idx"
ON "Player"("clubId", "teamId", "status", "lastName");
