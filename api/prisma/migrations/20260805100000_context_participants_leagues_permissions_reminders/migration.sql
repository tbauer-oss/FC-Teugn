CREATE TYPE "PermissionOverrideState" AS ENUM ('ALLOW', 'DENY');
CREATE TYPE "ReminderJobStatus" AS ENUM ('SCHEDULED', 'PROCESSING', 'SENT', 'CANCELLED', 'FAILED');
CREATE TYPE "LeagueMatchStatus" AS ENUM ('SCHEDULED', 'FINISHED', 'POSTPONED', 'CANCELLED');

ALTER TYPE "FileAssetKind" ADD VALUE IF NOT EXISTS 'OPPONENT_LOGO';

ALTER TABLE "Team"
ADD COLUMN "defaultReminderMinutes" INTEGER DEFAULT 60;

ALTER TABLE "Club"
ADD COLUMN "logoUrl" TEXT;

ALTER TABLE "Announcement"
ADD COLUMN "deletedAt" TIMESTAMP(3),
ADD COLUMN "deletedById" TEXT;

ALTER TABLE "Notification"
ADD COLUMN "dedupeKey" TEXT;

ALTER TABLE "MatchDetails"
ADD COLUMN "opponentId" TEXT,
ADD COLUMN "leagueId" TEXT;

CREATE TABLE "UserContextPreference" (
  "userId" TEXT NOT NULL,
  "ageGroupId" TEXT NOT NULL,
  "activeTeamId" TEXT,
  "includeAllTeams" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "UserContextPreference_pkey" PRIMARY KEY ("userId")
);

CREATE TABLE "UserPermissionOverride" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "permission" TEXT NOT NULL,
  "state" "PermissionOverrideState" NOT NULL,
  "changedById" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "UserPermissionOverride_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "EventParticipant" (
  "id" TEXT NOT NULL,
  "eventId" TEXT NOT NULL,
  "playerId" TEXT,
  "userId" TEXT,
  "responseRequired" BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "EventParticipant_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "EventParticipant_exactly_one_target" CHECK (
    ("playerId" IS NOT NULL AND "userId" IS NULL) OR
    ("playerId" IS NULL AND "userId" IS NOT NULL)
  )
);

CREATE TABLE "Opponent" (
  "id" TEXT NOT NULL,
  "ageGroupId" TEXT NOT NULL,
  "teamId" TEXT,
  "clubName" TEXT NOT NULL,
  "teamDesignation" TEXT NOT NULL,
  "shortName" TEXT,
  "normalizedKey" TEXT NOT NULL,
  "venue" TEXT,
  "address" TEXT,
  "logoAssetId" TEXT,
  "createdById" TEXT NOT NULL,
  "archivedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "Opponent_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "League" (
  "id" TEXT NOT NULL,
  "seasonId" TEXT NOT NULL,
  "ageGroupId" TEXT NOT NULL,
  "teamId" TEXT,
  "name" TEXT NOT NULL,
  "normalizedName" TEXT NOT NULL,
  "pointsWin" INTEGER NOT NULL DEFAULT 3,
  "pointsDraw" INTEGER NOT NULL DEFAULT 1,
  "pointsLoss" INTEGER NOT NULL DEFAULT 0,
  "createdById" TEXT NOT NULL,
  "archivedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "League_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "LeagueEntry" (
  "id" TEXT NOT NULL,
  "leagueId" TEXT NOT NULL,
  "opponentId" TEXT,
  "ownTeamId" TEXT,
  "displayName" TEXT NOT NULL,
  "sortOrder" INTEGER NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "LeagueEntry_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "LeagueEntry_exactly_one_team" CHECK (
    ("opponentId" IS NOT NULL AND "ownTeamId" IS NULL) OR
    ("opponentId" IS NULL AND "ownTeamId" IS NOT NULL)
  )
);

CREATE TABLE "LeagueMatch" (
  "id" TEXT NOT NULL,
  "leagueId" TEXT NOT NULL,
  "homeEntryId" TEXT NOT NULL,
  "awayEntryId" TEXT NOT NULL,
  "eventId" TEXT,
  "startsAt" TIMESTAMP(3),
  "status" "LeagueMatchStatus" NOT NULL DEFAULT 'SCHEDULED',
  "homeGoals" INTEGER,
  "awayGoals" INTEGER,
  "externalUid" TEXT,
  "venue" TEXT,
  "notes" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "LeagueMatch_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "LeagueMatch_distinct_teams" CHECK ("homeEntryId" <> "awayEntryId"),
  CONSTRAINT "LeagueMatch_nonnegative_score" CHECK (
    ("homeGoals" IS NULL OR "homeGoals" >= 0) AND
    ("awayGoals" IS NULL OR "awayGoals" >= 0)
  )
);

CREATE TABLE "ScheduledReminder" (
  "id" TEXT NOT NULL,
  "eventId" TEXT NOT NULL,
  "recipientId" TEXT NOT NULL,
  "dueAt" TIMESTAMP(3) NOT NULL,
  "minutesBefore" INTEGER NOT NULL,
  "status" "ReminderJobStatus" NOT NULL DEFAULT 'SCHEDULED',
  "idempotencyKey" TEXT NOT NULL,
  "attemptCount" INTEGER NOT NULL DEFAULT 0,
  "lastAttemptAt" TIMESTAMP(3),
  "sentAt" TIMESTAMP(3),
  "cancelledAt" TIMESTAMP(3),
  "errorMessage" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "ScheduledReminder_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "IdempotencyRecord" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "idempotencyKey" TEXT NOT NULL,
  "method" TEXT NOT NULL,
  "path" TEXT NOT NULL,
  "requestHash" TEXT NOT NULL,
  "responseStatus" INTEGER NOT NULL,
  "responseBody" JSONB NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "IdempotencyRecord_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "Notification_dedupeKey_key" ON "Notification"("dedupeKey");
CREATE INDEX "UserContextPreference_ageGroupId_activeTeamId_idx" ON "UserContextPreference"("ageGroupId", "activeTeamId");
CREATE UNIQUE INDEX "UserPermissionOverride_userId_permission_key" ON "UserPermissionOverride"("userId", "permission");
CREATE INDEX "UserPermissionOverride_changedById_updatedAt_idx" ON "UserPermissionOverride"("changedById", "updatedAt");
CREATE UNIQUE INDEX "EventParticipant_eventId_playerId_key" ON "EventParticipant"("eventId", "playerId");
CREATE UNIQUE INDEX "EventParticipant_eventId_userId_key" ON "EventParticipant"("eventId", "userId");
CREATE INDEX "EventParticipant_playerId_eventId_idx" ON "EventParticipant"("playerId", "eventId");
CREATE INDEX "EventParticipant_userId_eventId_idx" ON "EventParticipant"("userId", "eventId");
CREATE UNIQUE INDEX "Opponent_logoAssetId_key" ON "Opponent"("logoAssetId");
CREATE UNIQUE INDEX "Opponent_ageGroupId_normalizedKey_key" ON "Opponent"("ageGroupId", "normalizedKey");
CREATE INDEX "Opponent_ageGroupId_archivedAt_clubName_idx" ON "Opponent"("ageGroupId", "archivedAt", "clubName");
CREATE UNIQUE INDEX "League_seasonId_ageGroupId_normalizedName_teamId_key" ON "League"("seasonId", "ageGroupId", "normalizedName", "teamId");
CREATE INDEX "League_ageGroupId_archivedAt_idx" ON "League"("ageGroupId", "archivedAt");
CREATE UNIQUE INDEX "LeagueEntry_leagueId_opponentId_key" ON "LeagueEntry"("leagueId", "opponentId");
CREATE UNIQUE INDEX "LeagueEntry_leagueId_ownTeamId_key" ON "LeagueEntry"("leagueId", "ownTeamId");
CREATE INDEX "LeagueEntry_leagueId_sortOrder_idx" ON "LeagueEntry"("leagueId", "sortOrder");
CREATE UNIQUE INDEX "LeagueMatch_eventId_key" ON "LeagueMatch"("eventId");
CREATE UNIQUE INDEX "LeagueMatch_leagueId_externalUid_key" ON "LeagueMatch"("leagueId", "externalUid");
CREATE INDEX "LeagueMatch_leagueId_status_startsAt_idx" ON "LeagueMatch"("leagueId", "status", "startsAt");
CREATE UNIQUE INDEX "ScheduledReminder_idempotencyKey_key" ON "ScheduledReminder"("idempotencyKey");
CREATE INDEX "ScheduledReminder_status_dueAt_idx" ON "ScheduledReminder"("status", "dueAt");
CREATE INDEX "ScheduledReminder_recipientId_status_dueAt_idx" ON "ScheduledReminder"("recipientId", "status", "dueAt");
CREATE UNIQUE INDEX "IdempotencyRecord_userId_idempotencyKey_key" ON "IdempotencyRecord"("userId", "idempotencyKey");
CREATE INDEX "IdempotencyRecord_expiresAt_idx" ON "IdempotencyRecord"("expiresAt");

ALTER TABLE "UserContextPreference" ADD CONSTRAINT "UserContextPreference_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "UserContextPreference" ADD CONSTRAINT "UserContextPreference_ageGroupId_fkey" FOREIGN KEY ("ageGroupId") REFERENCES "AgeGroup"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "UserContextPreference" ADD CONSTRAINT "UserContextPreference_activeTeamId_fkey" FOREIGN KEY ("activeTeamId") REFERENCES "Team"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "UserPermissionOverride" ADD CONSTRAINT "UserPermissionOverride_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "UserPermissionOverride" ADD CONSTRAINT "UserPermissionOverride_changedById_fkey" FOREIGN KEY ("changedById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "EventParticipant" ADD CONSTRAINT "EventParticipant_eventId_fkey" FOREIGN KEY ("eventId") REFERENCES "Event"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "EventParticipant" ADD CONSTRAINT "EventParticipant_playerId_fkey" FOREIGN KEY ("playerId") REFERENCES "Player"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "EventParticipant" ADD CONSTRAINT "EventParticipant_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "Opponent" ADD CONSTRAINT "Opponent_ageGroupId_fkey" FOREIGN KEY ("ageGroupId") REFERENCES "AgeGroup"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "Opponent" ADD CONSTRAINT "Opponent_teamId_fkey" FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "Opponent" ADD CONSTRAINT "Opponent_logoAssetId_fkey" FOREIGN KEY ("logoAssetId") REFERENCES "FileAsset"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "Opponent" ADD CONSTRAINT "Opponent_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "League" ADD CONSTRAINT "League_seasonId_fkey" FOREIGN KEY ("seasonId") REFERENCES "Season"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "League" ADD CONSTRAINT "League_ageGroupId_fkey" FOREIGN KEY ("ageGroupId") REFERENCES "AgeGroup"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "League" ADD CONSTRAINT "League_teamId_fkey" FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "League" ADD CONSTRAINT "League_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "LeagueEntry" ADD CONSTRAINT "LeagueEntry_leagueId_fkey" FOREIGN KEY ("leagueId") REFERENCES "League"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "LeagueEntry" ADD CONSTRAINT "LeagueEntry_opponentId_fkey" FOREIGN KEY ("opponentId") REFERENCES "Opponent"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "LeagueEntry" ADD CONSTRAINT "LeagueEntry_ownTeamId_fkey" FOREIGN KEY ("ownTeamId") REFERENCES "Team"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "LeagueMatch" ADD CONSTRAINT "LeagueMatch_leagueId_fkey" FOREIGN KEY ("leagueId") REFERENCES "League"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "LeagueMatch" ADD CONSTRAINT "LeagueMatch_homeEntryId_fkey" FOREIGN KEY ("homeEntryId") REFERENCES "LeagueEntry"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "LeagueMatch" ADD CONSTRAINT "LeagueMatch_awayEntryId_fkey" FOREIGN KEY ("awayEntryId") REFERENCES "LeagueEntry"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "LeagueMatch" ADD CONSTRAINT "LeagueMatch_eventId_fkey" FOREIGN KEY ("eventId") REFERENCES "Event"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "ScheduledReminder" ADD CONSTRAINT "ScheduledReminder_eventId_fkey" FOREIGN KEY ("eventId") REFERENCES "Event"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ScheduledReminder" ADD CONSTRAINT "ScheduledReminder_recipientId_fkey" FOREIGN KEY ("recipientId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "IdempotencyRecord" ADD CONSTRAINT "IdempotencyRecord_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "Announcement" ADD CONSTRAINT "Announcement_deletedById_fkey" FOREIGN KEY ("deletedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "MatchDetails" ADD CONSTRAINT "MatchDetails_opponentId_fkey" FOREIGN KEY ("opponentId") REFERENCES "Opponent"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "MatchDetails" ADD CONSTRAINT "MatchDetails_leagueId_fkey" FOREIGN KEY ("leagueId") REFERENCES "League"("id") ON DELETE SET NULL ON UPDATE CASCADE;
