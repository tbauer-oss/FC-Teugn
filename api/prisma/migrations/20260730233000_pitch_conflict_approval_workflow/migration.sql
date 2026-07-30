CREATE TYPE "PitchConflictRequestStatus" AS ENUM (
  'PENDING',
  'APPROVED',
  'DECLINED',
  'CALLBACK_REQUESTED',
  'CANCELLED'
);

CREATE TABLE "PitchConflictRequest" (
  "id" TEXT NOT NULL,
  "eventId" TEXT NOT NULL,
  "trainingTeamId" TEXT NOT NULL,
  "requesterId" TEXT NOT NULL,
  "recipientId" TEXT NOT NULL,
  "respondedById" TEXT,
  "status" "PitchConflictRequestStatus" NOT NULL DEFAULT 'PENDING',
  "pitch" TEXT NOT NULL,
  "trainingScheduleValue" TEXT NOT NULL,
  "conflictStartAt" TIMESTAMP(3) NOT NULL,
  "conflictEndAt" TIMESTAMP(3) NOT NULL,
  "message" TEXT,
  "responseMessage" TEXT,
  "respondedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "PitchConflictRequest_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "PitchConflictRequest_eventId_trainingTeamId_trainingScheduleValue_key"
  ON "PitchConflictRequest"("eventId", "trainingTeamId", "trainingScheduleValue");
CREATE INDEX "PitchConflictRequest_recipientId_status_createdAt_idx"
  ON "PitchConflictRequest"("recipientId", "status", "createdAt");
CREATE INDEX "PitchConflictRequest_requesterId_createdAt_idx"
  ON "PitchConflictRequest"("requesterId", "createdAt");
CREATE INDEX "PitchConflictRequest_trainingTeamId_conflictStartAt_idx"
  ON "PitchConflictRequest"("trainingTeamId", "conflictStartAt");

ALTER TABLE "PitchConflictRequest"
  ADD CONSTRAINT "PitchConflictRequest_eventId_fkey"
  FOREIGN KEY ("eventId") REFERENCES "Event"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PitchConflictRequest"
  ADD CONSTRAINT "PitchConflictRequest_trainingTeamId_fkey"
  FOREIGN KEY ("trainingTeamId") REFERENCES "Team"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PitchConflictRequest"
  ADD CONSTRAINT "PitchConflictRequest_requesterId_fkey"
  FOREIGN KEY ("requesterId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PitchConflictRequest"
  ADD CONSTRAINT "PitchConflictRequest_recipientId_fkey"
  FOREIGN KEY ("recipientId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PitchConflictRequest"
  ADD CONSTRAINT "PitchConflictRequest_respondedById_fkey"
  FOREIGN KEY ("respondedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
