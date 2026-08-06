CREATE TYPE "EventCommunicationStatus" AS ENUM ('DRAFT', 'INTERNAL_PUBLISHED', 'FAMILY_RELEASED');

ALTER TABLE "Team"
ADD COLUMN "secondaryReminderMinutes" INTEGER DEFAULT 1440;

ALTER TABLE "Event"
ADD COLUMN "communicationStatus" "EventCommunicationStatus" NOT NULL DEFAULT 'DRAFT',
ADD COLUMN "isHiddenRegularOccurrence" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "internalPublishedAt" TIMESTAMP(3),
ADD COLUMN "familyReleasedAt" TIMESTAMP(3),
ADD COLUMN "familyReleaseAudience" TEXT;
