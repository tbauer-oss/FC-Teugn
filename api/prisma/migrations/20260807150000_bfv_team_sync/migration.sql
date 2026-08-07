CREATE TABLE "BfvTeamSync" (
    "id" TEXT NOT NULL,
    "teamId" TEXT NOT NULL,
    "teamPageUrl" TEXT,
    "icalUrl" TEXT,
    "officialViewUrl" TEXT,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "syncIntervalMinutes" INTEGER NOT NULL DEFAULT 30,
    "lastAttemptAt" TIMESTAMP(3),
    "lastSuccessAt" TIMESTAMP(3),
    "lastStatus" TEXT NOT NULL DEFAULT 'NOT_CONFIGURED',
    "lastMessage" TEXT,
    "lastCreatedCount" INTEGER NOT NULL DEFAULT 0,
    "lastUpdatedCount" INTEGER NOT NULL DEFAULT 0,
    "lastSkippedCount" INTEGER NOT NULL DEFAULT 0,
    "lastConflictCount" INTEGER NOT NULL DEFAULT 0,
    "createdById" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "BfvTeamSync_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "BfvTeamSync_teamId_key" ON "BfvTeamSync"("teamId");
CREATE INDEX "BfvTeamSync_enabled_lastAttemptAt_idx" ON "BfvTeamSync"("enabled", "lastAttemptAt");

ALTER TABLE "BfvTeamSync" ADD CONSTRAINT "BfvTeamSync_teamId_fkey"
  FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "BfvTeamSync" ADD CONSTRAINT "BfvTeamSync_createdById_fkey"
  FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
