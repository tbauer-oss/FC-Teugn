CREATE TABLE "SameDayMatchApproval" (
  "id" TEXT NOT NULL,
  "playerId" TEXT NOT NULL,
  "firstEventId" TEXT NOT NULL,
  "secondEventId" TEXT NOT NULL,
  "day" TEXT NOT NULL,
  "approvedById" TEXT,
  "approvedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SameDayMatchApproval_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "SameDayMatchApproval_ordered_pair" CHECK ("firstEventId" < "secondEventId"),
  CONSTRAINT "SameDayMatchApproval_playerId_fkey" FOREIGN KEY ("playerId") REFERENCES "Player"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "SameDayMatchApproval_firstEventId_fkey" FOREIGN KEY ("firstEventId") REFERENCES "Event"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "SameDayMatchApproval_secondEventId_fkey" FOREIGN KEY ("secondEventId") REFERENCES "Event"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "SameDayMatchApproval_approvedById_fkey" FOREIGN KEY ("approvedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "SameDayMatchApproval_playerId_firstEventId_secondEventId_day_key" ON "SameDayMatchApproval"("playerId", "firstEventId", "secondEventId", "day");
CREATE INDEX "SameDayMatchApproval_playerId_day_idx" ON "SameDayMatchApproval"("playerId", "day");
CREATE INDEX "SameDayMatchApproval_firstEventId_idx" ON "SameDayMatchApproval"("firstEventId");
CREATE INDEX "SameDayMatchApproval_secondEventId_idx" ON "SameDayMatchApproval"("secondEventId");
