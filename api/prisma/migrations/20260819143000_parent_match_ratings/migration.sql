CREATE TABLE "ParentPlayerMatchRating" (
    "id" TEXT NOT NULL,
    "eventId" TEXT NOT NULL,
    "playerId" TEXT NOT NULL,
    "ratedById" TEXT NOT NULL,
    "score" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ParentPlayerMatchRating_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "ParentPlayerMatchRating_score_check" CHECK ("score" BETWEEN 1 AND 10)
);

CREATE UNIQUE INDEX "ParentPlayerMatchRating_eventId_playerId_ratedById_key"
ON "ParentPlayerMatchRating"("eventId", "playerId", "ratedById");

CREATE INDEX "ParentPlayerMatchRating_eventId_updatedAt_idx"
ON "ParentPlayerMatchRating"("eventId", "updatedAt");

CREATE INDEX "ParentPlayerMatchRating_playerId_updatedAt_idx"
ON "ParentPlayerMatchRating"("playerId", "updatedAt");

CREATE INDEX "ParentPlayerMatchRating_ratedById_updatedAt_idx"
ON "ParentPlayerMatchRating"("ratedById", "updatedAt");

ALTER TABLE "ParentPlayerMatchRating"
ADD CONSTRAINT "ParentPlayerMatchRating_eventId_fkey"
FOREIGN KEY ("eventId") REFERENCES "Event"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "ParentPlayerMatchRating"
ADD CONSTRAINT "ParentPlayerMatchRating_playerId_fkey"
FOREIGN KEY ("playerId") REFERENCES "Player"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "ParentPlayerMatchRating"
ADD CONSTRAINT "ParentPlayerMatchRating_ratedById_fkey"
FOREIGN KEY ("ratedById") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
