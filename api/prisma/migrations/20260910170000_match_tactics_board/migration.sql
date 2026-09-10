CREATE TABLE "MatchTacticsBoard" (
  "eventId" TEXT NOT NULL,
  "revision" INTEGER NOT NULL DEFAULT 1,
  "document" JSONB NOT NULL,
  "updatedById" TEXT NOT NULL,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "MatchTacticsBoard_pkey" PRIMARY KEY ("eventId"),
  CONSTRAINT "MatchTacticsBoard_eventId_fkey" FOREIGN KEY ("eventId") REFERENCES "Event"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
