-- Additive professional calendar migration. Existing events, attendance,
-- matches and squads remain intact.
CREATE TYPE "EventCategory" AS ENUM (
  'TRAINING',
  'LEAGUE_MATCH',
  'FRIENDLY_MATCH',
  'CUP_MATCH',
  'TOURNAMENT',
  'INDOOR_TOURNAMENT',
  'FOOTBALL_FESTIVAL',
  'TEAM_MEETING',
  'PARENTS_MEETING',
  'CHRISTMAS_PARTY',
  'SEASON_CLOSING',
  'CLUB_EVENT',
  'TRIP',
  'PHOTO_SESSION',
  'SPECIAL_EVENT'
);

CREATE TYPE "EventStatus" AS ENUM ('SCHEDULED', 'CANCELLED');
CREATE TYPE "EventVisibility" AS ENUM ('TEAM', 'CLUB', 'STAFF_ONLY');
CREATE TYPE "HomeAway" AS ENUM ('HOME', 'AWAY', 'NEUTRAL');
CREATE TYPE "RecurrenceFrequency" AS ENUM ('WEEKLY', 'BIWEEKLY', 'CUSTOM');
CREATE TYPE "CarpoolRequestStatus" AS ENUM (
  'REQUESTED',
  'CONFIRMED',
  'DECLINED',
  'CANCELLED'
);

ALTER TABLE "User" ADD COLUMN "calendarToken" TEXT;
CREATE UNIQUE INDEX "User_calendarToken_key" ON "User"("calendarToken");

CREATE TABLE "EventSeries" (
  "id" TEXT NOT NULL,
  "teamId" TEXT NOT NULL,
  "createdById" TEXT NOT NULL,
  "frequency" "RecurrenceFrequency" NOT NULL,
  "interval" INTEGER NOT NULL DEFAULT 1,
  "weekdays" INTEGER[] NOT NULL DEFAULT ARRAY[]::INTEGER[],
  "until" TIMESTAMP(3) NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "EventSeries_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "Event"
  ADD COLUMN "seriesId" TEXT,
  ADD COLUMN "category" "EventCategory" NOT NULL DEFAULT 'SPECIAL_EVENT',
  ADD COLUMN "status" "EventStatus" NOT NULL DEFAULT 'SCHEDULED',
  ADD COLUMN "visibility" "EventVisibility" NOT NULL DEFAULT 'TEAM',
  ADD COLUMN "meetingAt" TIMESTAMP(3),
  ADD COLUMN "address" TEXT,
  ADD COLUMN "mapUrl" TEXT,
  ADD COLUMN "homeAway" "HomeAway",
  ADD COLUMN "opponent" TEXT,
  ADD COLUMN "venue" TEXT,
  ADD COLUMN "contactName" TEXT,
  ADD COLUMN "contactPhone" TEXT,
  ADD COLUMN "equipment" TEXT,
  ADD COLUMN "clothing" TEXT,
  ADD COLUMN "catering" TEXT,
  ADD COLUMN "carpoolRequired" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "maxParticipants" INTEGER,
  ADD COLUMN "responseDeadline" TIMESTAMP(3),
  ADD COLUMN "internalNote" TEXT,
  ADD COLUMN "reminderMinutes" INTEGER[] NOT NULL DEFAULT ARRAY[]::INTEGER[],
  ADD COLUMN "isSeriesException" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "cancellationReason" TEXT,
  ADD COLUMN "cancelledAt" TIMESTAMP(3);

UPDATE "Event"
SET "category" = CASE
  WHEN "type" = 'TRAINING' THEN 'TRAINING'::"EventCategory"
  WHEN "type" = 'MATCH' THEN 'LEAGUE_MATCH'::"EventCategory"
  ELSE 'SPECIAL_EVENT'::"EventCategory"
END;

ALTER TABLE "Attendance"
  ADD COLUMN "reason" TEXT,
  ADD COLUMN "goalkeeperAvailable" BOOLEAN,
  ADD COLUMN "respondedById" TEXT,
  ADD COLUMN "respondedAt" TIMESTAMP(3),
  ADD COLUMN "actualAttendance" "AttendanceStatus",
  ADD COLUMN "actualAttendanceNote" TEXT;

CREATE TABLE "EventTargetTeam" (
  "id" TEXT NOT NULL,
  "eventId" TEXT NOT NULL,
  "teamId" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "EventTargetTeam_pkey" PRIMARY KEY ("id")
);

INSERT INTO "EventTargetTeam" ("id", "eventId", "teamId")
SELECT 'ett_' || md5("id" || ':' || "teamId"), "id", "teamId"
FROM "Event";

CREATE TABLE "EventAttachment" (
  "id" TEXT NOT NULL,
  "eventId" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "url" TEXT NOT NULL,
  "mimeType" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "EventAttachment_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "CarpoolOffer" (
  "id" TEXT NOT NULL,
  "eventId" TEXT NOT NULL,
  "driverId" TEXT NOT NULL,
  "seatsTotal" INTEGER NOT NULL,
  "departureLocation" TEXT NOT NULL,
  "departureAt" TIMESTAMP(3) NOT NULL,
  "notes" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "CarpoolOffer_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "CarpoolPassenger" (
  "id" TEXT NOT NULL,
  "offerId" TEXT NOT NULL,
  "playerId" TEXT NOT NULL,
  "requestedById" TEXT NOT NULL,
  "status" "CarpoolRequestStatus" NOT NULL DEFAULT 'REQUESTED',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "CarpoolPassenger_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "EventReminder" (
  "id" TEXT NOT NULL,
  "eventId" TEXT NOT NULL,
  "recipientId" TEXT NOT NULL,
  "message" TEXT NOT NULL,
  "readAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "EventReminder_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "Event_teamId_startAt_idx" ON "Event"("teamId", "startAt");
CREATE INDEX "Event_seriesId_startAt_idx" ON "Event"("seriesId", "startAt");
CREATE INDEX "Event_status_startAt_idx" ON "Event"("status", "startAt");
CREATE INDEX "EventSeries_teamId_until_idx" ON "EventSeries"("teamId", "until");
CREATE UNIQUE INDEX "EventTargetTeam_eventId_teamId_key" ON "EventTargetTeam"("eventId", "teamId");
CREATE INDEX "EventTargetTeam_teamId_eventId_idx" ON "EventTargetTeam"("teamId", "eventId");
CREATE INDEX "EventAttachment_eventId_idx" ON "EventAttachment"("eventId");
CREATE INDEX "Attendance_eventId_status_idx" ON "Attendance"("eventId", "status");
CREATE INDEX "CarpoolOffer_eventId_departureAt_idx" ON "CarpoolOffer"("eventId", "departureAt");
CREATE UNIQUE INDEX "CarpoolPassenger_offerId_playerId_key" ON "CarpoolPassenger"("offerId", "playerId");
CREATE INDEX "CarpoolPassenger_offerId_status_idx" ON "CarpoolPassenger"("offerId", "status");
CREATE INDEX "EventReminder_recipientId_readAt_createdAt_idx" ON "EventReminder"("recipientId", "readAt", "createdAt");
CREATE INDEX "EventReminder_eventId_createdAt_idx" ON "EventReminder"("eventId", "createdAt");

ALTER TABLE "EventSeries"
  ADD CONSTRAINT "EventSeries_teamId_fkey"
  FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT "EventSeries_createdById_fkey"
  FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "Event"
  ADD CONSTRAINT "Event_seriesId_fkey"
  FOREIGN KEY ("seriesId") REFERENCES "EventSeries"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "EventTargetTeam"
  ADD CONSTRAINT "EventTargetTeam_eventId_fkey"
  FOREIGN KEY ("eventId") REFERENCES "Event"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT "EventTargetTeam_teamId_fkey"
  FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "EventAttachment"
  ADD CONSTRAINT "EventAttachment_eventId_fkey"
  FOREIGN KEY ("eventId") REFERENCES "Event"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "Attendance"
  DROP CONSTRAINT "Attendance_eventId_fkey",
  DROP CONSTRAINT "Attendance_playerId_fkey",
  ADD CONSTRAINT "Attendance_eventId_fkey"
  FOREIGN KEY ("eventId") REFERENCES "Event"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT "Attendance_playerId_fkey"
  FOREIGN KEY ("playerId") REFERENCES "Player"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT "Attendance_respondedById_fkey"
  FOREIGN KEY ("respondedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "CarpoolOffer"
  ADD CONSTRAINT "CarpoolOffer_eventId_fkey"
  FOREIGN KEY ("eventId") REFERENCES "Event"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT "CarpoolOffer_driverId_fkey"
  FOREIGN KEY ("driverId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "CarpoolPassenger"
  ADD CONSTRAINT "CarpoolPassenger_offerId_fkey"
  FOREIGN KEY ("offerId") REFERENCES "CarpoolOffer"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT "CarpoolPassenger_playerId_fkey"
  FOREIGN KEY ("playerId") REFERENCES "Player"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT "CarpoolPassenger_requestedById_fkey"
  FOREIGN KEY ("requestedById") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "EventReminder"
  ADD CONSTRAINT "EventReminder_eventId_fkey"
  FOREIGN KEY ("eventId") REFERENCES "Event"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT "EventReminder_recipientId_fkey"
  FOREIGN KEY ("recipientId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
