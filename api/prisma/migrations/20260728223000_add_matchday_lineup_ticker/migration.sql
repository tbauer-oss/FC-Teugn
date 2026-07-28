CREATE TYPE "MatchKind" AS ENUM (
  'LEAGUE', 'FRIENDLY', 'CUP', 'TOURNAMENT', 'INDOOR', 'FESTIVAL', 'TEST', 'INTERNAL'
);
CREATE TYPE "MatchStatus" AS ENUM (
  'PLANNED', 'CONFIRMED', 'POSTPONED', 'CANCELLED', 'LIVE', 'HALF_TIME',
  'INTERRUPTED', 'FINISHED', 'RECORDED'
);
CREATE TYPE "NominationStatus" AS ENUM ('NOMINATED', 'ON_CALL', 'DECLINED');
CREATE TYPE "LineupStatus" AS ENUM (
  'DRAFT', 'INTERNALLY_APPROVED', 'PUBLISHED', 'ARCHIVED'
);
CREATE TYPE "TickerStatus" AS ENUM (
  'NOT_STARTED', 'LIVE', 'PAUSED', 'HALF_TIME', 'INTERRUPTED', 'FINISHED'
);
CREATE TYPE "TickerEventType" AS ENUM (
  'MATCH_START', 'HOME_GOAL', 'AWAY_GOAL', 'PERIOD_END', 'PERIOD_START',
  'INTERRUPTION', 'RESUME', 'SUBSTITUTION', 'CARD', 'INJURY', 'PENALTY',
  'OWN_GOAL', 'COMMENT', 'CORRECTION', 'EVENT_REVOKED', 'MATCH_END'
);

ALTER TABLE "MatchDetails"
  ADD COLUMN "kind" "MatchKind" NOT NULL DEFAULT 'FRIENDLY',
  ADD COLUMN "status" "MatchStatus" NOT NULL DEFAULT 'PLANNED',
  ADD COLUMN "opponentShortName" TEXT,
  ADD COLUMN "opponentLogoUrl" TEXT,
  ADD COLUMN "division" TEXT,
  ADD COLUMN "matchDay" TEXT,
  ADD COLUMN "pitch" TEXT,
  ADD COLUMN "referee" TEXT,
  ADD COLUMN "durationMinutes" INTEGER NOT NULL DEFAULT 60,
  ADD COLUMN "periodMinutes" INTEGER NOT NULL DEFAULT 30,
  ADD COLUMN "periodCount" INTEGER NOT NULL DEFAULT 2,
  ADD COLUMN "bfvMatchId" TEXT,
  ADD COLUMN "bfvUrl" TEXT,
  ADD COLUMN "externalSource" TEXT,
  ADD COLUMN "externalUpdatedAt" TIMESTAMP(3),
  ADD COLUMN "halfTimeOurGoals" INTEGER,
  ADD COLUMN "halfTimeTheirGoals" INTEGER;

ALTER TABLE "MatchDetails" DROP CONSTRAINT IF EXISTS "MatchDetails_eventId_fkey";
ALTER TABLE "MatchDetails"
  ADD CONSTRAINT "MatchDetails_eventId_fkey"
  FOREIGN KEY ("eventId") REFERENCES "Event"("id") ON DELETE CASCADE ON UPDATE CASCADE;
CREATE INDEX "MatchDetails_status_updatedAt_idx" ON "MatchDetails"("status", "updatedAt");
CREATE INDEX "MatchDetails_bfvMatchId_idx" ON "MatchDetails"("bfvMatchId");

DELETE FROM "SquadMember"
WHERE "squadId" IN (
  SELECT duplicate."id"
  FROM "Squad" duplicate
  JOIN "Squad" keeper
    ON keeper."eventId" = duplicate."eventId"
   AND keeper."createdAt" < duplicate."createdAt"
);
DELETE FROM "Squad" duplicate
USING "Squad" keeper
WHERE keeper."eventId" = duplicate."eventId"
  AND keeper."createdAt" < duplicate."createdAt";

CREATE UNIQUE INDEX "Squad_eventId_key" ON "Squad"("eventId");
ALTER TABLE "Squad" ADD COLUMN "publishedAt" TIMESTAMP(3);
ALTER TABLE "Squad" DROP CONSTRAINT IF EXISTS "Squad_eventId_fkey";
ALTER TABLE "Squad"
  ADD CONSTRAINT "Squad_eventId_fkey"
  FOREIGN KEY ("eventId") REFERENCES "Event"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "SquadMember"
  ADD COLUMN "status" "NominationStatus" NOT NULL DEFAULT 'NOMINATED',
  ADD COLUMN "note" TEXT,
  ADD COLUMN "plannedMinutes" INTEGER,
  ADD COLUMN "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE "SquadMember" DROP CONSTRAINT IF EXISTS "SquadMember_squadId_fkey";
ALTER TABLE "SquadMember" DROP CONSTRAINT IF EXISTS "SquadMember_playerId_fkey";
ALTER TABLE "SquadMember"
  ADD CONSTRAINT "SquadMember_squadId_fkey"
  FOREIGN KEY ("squadId") REFERENCES "Squad"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "SquadMember"
  ADD CONSTRAINT "SquadMember_playerId_fkey"
  FOREIGN KEY ("playerId") REFERENCES "Player"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
CREATE INDEX "SquadMember_playerId_idx" ON "SquadMember"("playerId");

CREATE TABLE "Lineup" (
  "id" TEXT NOT NULL,
  "squadId" TEXT NOT NULL,
  "formation" TEXT NOT NULL,
  "fieldSize" INTEGER NOT NULL DEFAULT 7,
  "status" "LineupStatus" NOT NULL DEFAULT 'DRAFT',
  "publicNote" TEXT,
  "tacticalNote" TEXT,
  "visibleAt" TIMESTAMP(3),
  "publishedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "Lineup_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "Lineup_squadId_key" ON "Lineup"("squadId");
ALTER TABLE "Lineup"
  ADD CONSTRAINT "Lineup_squadId_fkey"
  FOREIGN KEY ("squadId") REFERENCES "Squad"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "LineupPosition" (
  "id" TEXT NOT NULL,
  "lineupId" TEXT NOT NULL,
  "playerId" TEXT NOT NULL,
  "period" INTEGER NOT NULL DEFAULT 1,
  "positionCode" TEXT NOT NULL,
  "x" DOUBLE PRECISION NOT NULL,
  "y" DOUBLE PRECISION NOT NULL,
  "isStarter" BOOLEAN NOT NULL DEFAULT true,
  "isGoalkeeper" BOOLEAN NOT NULL DEFAULT false,
  "isCaptain" BOOLEAN NOT NULL DEFAULT false,
  "shirtNumber" INTEGER,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "LineupPosition_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "LineupPosition_lineupId_playerId_period_key"
  ON "LineupPosition"("lineupId", "playerId", "period");
CREATE INDEX "LineupPosition_lineupId_period_idx"
  ON "LineupPosition"("lineupId", "period");
ALTER TABLE "LineupPosition"
  ADD CONSTRAINT "LineupPosition_lineupId_fkey"
  FOREIGN KEY ("lineupId") REFERENCES "Lineup"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "LineupPosition"
  ADD CONSTRAINT "LineupPosition_playerId_fkey"
  FOREIGN KEY ("playerId") REFERENCES "Player"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE TABLE "PlannedSubstitution" (
  "id" TEXT NOT NULL,
  "lineupId" TEXT NOT NULL,
  "period" INTEGER NOT NULL,
  "minute" INTEGER,
  "playerInId" TEXT NOT NULL,
  "playerOutId" TEXT NOT NULL,
  "note" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "PlannedSubstitution_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "PlannedSubstitution_lineupId_period_idx"
  ON "PlannedSubstitution"("lineupId", "period");
ALTER TABLE "PlannedSubstitution"
  ADD CONSTRAINT "PlannedSubstitution_lineupId_fkey"
  FOREIGN KEY ("lineupId") REFERENCES "Lineup"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "LiveTicker" (
  "id" TEXT NOT NULL,
  "eventId" TEXT NOT NULL,
  "status" "TickerStatus" NOT NULL DEFAULT 'NOT_STARTED',
  "currentPeriod" INTEGER NOT NULL DEFAULT 1,
  "elapsedSeconds" INTEGER NOT NULL DEFAULT 0,
  "clockStartedAt" TIMESTAMP(3),
  "ourGoals" INTEGER NOT NULL DEFAULT 0,
  "theirGoals" INTEGER NOT NULL DEFAULT 0,
  "lastSequence" INTEGER NOT NULL DEFAULT 0,
  "publicScorersEnabled" BOOLEAN NOT NULL DEFAULT false,
  "startedAt" TIMESTAMP(3),
  "finishedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "LiveTicker_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "LiveTicker_eventId_key" ON "LiveTicker"("eventId");
ALTER TABLE "LiveTicker"
  ADD CONSTRAINT "LiveTicker_eventId_fkey"
  FOREIGN KEY ("eventId") REFERENCES "Event"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "LiveTickerEvent" (
  "id" TEXT NOT NULL,
  "tickerId" TEXT NOT NULL,
  "clientEventId" TEXT NOT NULL,
  "sequence" INTEGER NOT NULL,
  "type" "TickerEventType" NOT NULL,
  "period" INTEGER NOT NULL,
  "elapsedSeconds" INTEGER NOT NULL,
  "ourGoals" INTEGER NOT NULL,
  "theirGoals" INTEGER NOT NULL,
  "scorerId" TEXT,
  "assistId" TEXT,
  "authorId" TEXT NOT NULL,
  "comment" TEXT,
  "revokedAt" TIMESTAMP(3),
  "correctsId" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "LiveTickerEvent_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "LiveTickerEvent_tickerId_clientEventId_key"
  ON "LiveTickerEvent"("tickerId", "clientEventId");
CREATE UNIQUE INDEX "LiveTickerEvent_tickerId_sequence_key"
  ON "LiveTickerEvent"("tickerId", "sequence");
CREATE INDEX "LiveTickerEvent_tickerId_createdAt_idx"
  ON "LiveTickerEvent"("tickerId", "createdAt");
ALTER TABLE "LiveTickerEvent"
  ADD CONSTRAINT "LiveTickerEvent_tickerId_fkey"
  FOREIGN KEY ("tickerId") REFERENCES "LiveTicker"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "LiveTickerEvent"
  ADD CONSTRAINT "LiveTickerEvent_scorerId_fkey"
  FOREIGN KEY ("scorerId") REFERENCES "Player"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "LiveTickerEvent"
  ADD CONSTRAINT "LiveTickerEvent_assistId_fkey"
  FOREIGN KEY ("assistId") REFERENCES "Player"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "LiveTickerEvent"
  ADD CONSTRAINT "LiveTickerEvent_authorId_fkey"
  FOREIGN KEY ("authorId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE TABLE "RuleProfile" (
  "id" TEXT NOT NULL,
  "teamId" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "validFrom" TIMESTAMP(3) NOT NULL,
  "validUntil" TIMESTAMP(3),
  "gameFormat" TEXT NOT NULL,
  "teamSize" INTEGER NOT NULL,
  "maxSquadSize" INTEGER,
  "periodCount" INTEGER NOT NULL,
  "periodMinutes" INTEGER NOT NULL,
  "substitutionsRolling" BOOLEAN NOT NULL DEFAULT true,
  "showResults" BOOLEAN NOT NULL DEFAULT true,
  "showTable" BOOLEAN NOT NULL DEFAULT true,
  "festivalMode" BOOLEAN NOT NULL DEFAULT false,
  "sourceNote" TEXT,
  "version" INTEGER NOT NULL DEFAULT 1,
  "approvedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "RuleProfile_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "RuleProfile_teamId_validFrom_idx" ON "RuleProfile"("teamId", "validFrom");
ALTER TABLE "RuleProfile"
  ADD CONSTRAINT "RuleProfile_teamId_fkey"
  FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE CASCADE ON UPDATE CASCADE;
