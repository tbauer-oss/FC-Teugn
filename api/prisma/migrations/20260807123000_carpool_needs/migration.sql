CREATE TYPE "CarpoolNeedStatus" AS ENUM ('OPEN', 'MATCHED', 'CANCELLED');

CREATE TABLE "CarpoolNeed" (
  "id" TEXT NOT NULL,
  "eventId" TEXT NOT NULL,
  "playerId" TEXT NOT NULL,
  "requestedById" TEXT NOT NULL,
  "note" TEXT,
  "status" "CarpoolNeedStatus" NOT NULL DEFAULT 'OPEN',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "CarpoolNeed_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "CarpoolNeed_eventId_playerId_key"
  ON "CarpoolNeed"("eventId", "playerId");
CREATE INDEX "CarpoolNeed_eventId_status_createdAt_idx"
  ON "CarpoolNeed"("eventId", "status", "createdAt");
CREATE INDEX "CarpoolNeed_requestedById_status_idx"
  ON "CarpoolNeed"("requestedById", "status");

ALTER TABLE "CarpoolNeed"
  ADD CONSTRAINT "CarpoolNeed_eventId_fkey"
  FOREIGN KEY ("eventId") REFERENCES "Event"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "CarpoolNeed"
  ADD CONSTRAINT "CarpoolNeed_playerId_fkey"
  FOREIGN KEY ("playerId") REFERENCES "Player"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "CarpoolNeed"
  ADD CONSTRAINT "CarpoolNeed_requestedById_fkey"
  FOREIGN KEY ("requestedById") REFERENCES "User"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
