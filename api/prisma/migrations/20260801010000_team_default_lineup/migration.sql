ALTER TABLE "Team"
ADD COLUMN "defaultFormation" TEXT;

ALTER TABLE "Lineup"
ADD COLUMN "usesTeamDefault" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "automaticReplacements" INTEGER NOT NULL DEFAULT 0;

CREATE TABLE "TeamDefaultLineupPosition" (
    "id" TEXT NOT NULL,
    "teamId" TEXT NOT NULL,
    "playerId" TEXT NOT NULL,
    "positionCode" TEXT NOT NULL,
    "x" DOUBLE PRECISION NOT NULL,
    "y" DOUBLE PRECISION NOT NULL,
    "isGoalkeeper" BOOLEAN NOT NULL DEFAULT false,
    "isCaptain" BOOLEAN NOT NULL DEFAULT false,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TeamDefaultLineupPosition_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "TeamDefaultLineupPosition_teamId_playerId_key"
ON "TeamDefaultLineupPosition"("teamId", "playerId");

CREATE INDEX "TeamDefaultLineupPosition_teamId_sortOrder_idx"
ON "TeamDefaultLineupPosition"("teamId", "sortOrder");

CREATE INDEX "TeamDefaultLineupPosition_playerId_idx"
ON "TeamDefaultLineupPosition"("playerId");

ALTER TABLE "TeamDefaultLineupPosition"
ADD CONSTRAINT "TeamDefaultLineupPosition_teamId_fkey"
FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "TeamDefaultLineupPosition"
ADD CONSTRAINT "TeamDefaultLineupPosition_playerId_fkey"
FOREIGN KEY ("playerId") REFERENCES "Player"("id") ON DELETE CASCADE ON UPDATE CASCADE;
