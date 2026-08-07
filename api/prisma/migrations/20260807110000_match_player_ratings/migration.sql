CREATE TABLE "PlayerMatchRating" (
    "id" TEXT NOT NULL,
    "eventId" TEXT NOT NULL,
    "playerId" TEXT NOT NULL,
    "ratedById" TEXT NOT NULL,
    "score" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PlayerMatchRating_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "PlayerMatchRating_score_check" CHECK ("score" BETWEEN 1 AND 10)
);

CREATE UNIQUE INDEX "PlayerMatchRating_eventId_playerId_key"
ON "PlayerMatchRating"("eventId", "playerId");

CREATE INDEX "PlayerMatchRating_playerId_updatedAt_idx"
ON "PlayerMatchRating"("playerId", "updatedAt");

CREATE INDEX "PlayerMatchRating_ratedById_updatedAt_idx"
ON "PlayerMatchRating"("ratedById", "updatedAt");

ALTER TABLE "PlayerMatchRating"
ADD CONSTRAINT "PlayerMatchRating_eventId_fkey"
FOREIGN KEY ("eventId") REFERENCES "Event"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "PlayerMatchRating"
ADD CONSTRAINT "PlayerMatchRating_playerId_fkey"
FOREIGN KEY ("playerId") REFERENCES "Player"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "PlayerMatchRating"
ADD CONSTRAINT "PlayerMatchRating_ratedById_fkey"
FOREIGN KEY ("ratedById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
