CREATE TYPE "KitLaundryDutyStatus" AS ENUM ('OPEN', 'PROPOSED', 'CONFIRMED', 'COMPLETED');
CREATE TYPE "KitLaundryAssignmentSource" AS ENUM ('AUTOMATIC', 'MANUAL');

CREATE TABLE "KitLaundryDuty" (
  "id" TEXT NOT NULL,
  "eventId" TEXT NOT NULL,
  "teamId" TEXT NOT NULL,
  "assignedPlayerId" TEXT,
  "assignedFamilyKey" TEXT,
  "status" "KitLaundryDutyStatus" NOT NULL DEFAULT 'OPEN',
  "assignmentSource" "KitLaundryAssignmentSource" NOT NULL DEFAULT 'AUTOMATIC',
  "declinedFamilyKeys" TEXT[] DEFAULT ARRAY[]::TEXT[],
  "proposedAt" TIMESTAMP(3),
  "confirmedAt" TIMESTAMP(3),
  "confirmedById" TEXT,
  "completedAt" TIMESTAMP(3),
  "reminderSentAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "KitLaundryDuty_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "KitLaundryDuty_eventId_key" ON "KitLaundryDuty"("eventId");
CREATE INDEX "KitLaundryDuty_teamId_status_updatedAt_idx" ON "KitLaundryDuty"("teamId", "status", "updatedAt");
CREATE INDEX "KitLaundryDuty_assignedFamilyKey_status_completedAt_idx" ON "KitLaundryDuty"("assignedFamilyKey", "status", "completedAt");
CREATE INDEX "KitLaundryDuty_status_reminderSentAt_idx" ON "KitLaundryDuty"("status", "reminderSentAt");

ALTER TABLE "KitLaundryDuty" ADD CONSTRAINT "KitLaundryDuty_eventId_fkey" FOREIGN KEY ("eventId") REFERENCES "Event"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "KitLaundryDuty" ADD CONSTRAINT "KitLaundryDuty_teamId_fkey" FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "KitLaundryDuty" ADD CONSTRAINT "KitLaundryDuty_assignedPlayerId_fkey" FOREIGN KEY ("assignedPlayerId") REFERENCES "Player"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "KitLaundryDuty" ADD CONSTRAINT "KitLaundryDuty_confirmedById_fkey" FOREIGN KEY ("confirmedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
