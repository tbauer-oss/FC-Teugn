CREATE TYPE "AttendanceResponseSource" AS ENUM ('GUARDIAN', 'PLAYER', 'TRAINER_CORRECTION', 'SYSTEM_ADMINISTRATION');
CREATE TYPE "SupportCategory" AS ENUM ('USAGE', 'DISPLAY', 'ACCOUNT', 'PUSH', 'SYNC', 'CALENDAR', 'MATCHDAY', 'OTHER');
CREATE TYPE "SupportStatus" AS ENUM ('OPEN', 'IN_PROGRESS', 'QUESTION', 'RESOLVED', 'CLOSED');

ALTER TYPE "NotificationCategory" ADD VALUE IF NOT EXISTS 'SUPPORT';
ALTER TYPE "FileAssetKind" ADD VALUE IF NOT EXISTS 'SUPPORT_ATTACHMENT';

ALTER TABLE "Team"
ADD COLUMN "defaultReminderPushEnabled" BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE "Event"
ADD COLUMN "reminderPushEnabled" BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE "Attendance"
ADD COLUMN "responseSource" "AttendanceResponseSource",
ADD COLUMN "responderRelationship" "GuardianRelationship";

CREATE TABLE "SupportTicket" (
  "id" TEXT NOT NULL,
  "creatorId" TEXT NOT NULL,
  "assignedToId" TEXT,
  "category" "SupportCategory" NOT NULL,
  "subject" TEXT NOT NULL,
  "description" TEXT NOT NULL,
  "appArea" TEXT,
  "contactRequested" BOOLEAN NOT NULL DEFAULT false,
  "technicalMetadata" JSONB NOT NULL,
  "status" "SupportStatus" NOT NULL DEFAULT 'OPEN',
  "attachmentAssetId" TEXT,
  "resolvedAt" TIMESTAMP(3),
  "closedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "SupportTicket_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "SupportMessage" (
  "id" TEXT NOT NULL,
  "ticketId" TEXT NOT NULL,
  "authorId" TEXT NOT NULL,
  "body" TEXT NOT NULL,
  "internal" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SupportMessage_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "SupportTicket_attachmentAssetId_key" ON "SupportTicket"("attachmentAssetId");
CREATE INDEX "SupportTicket_creatorId_status_updatedAt_idx" ON "SupportTicket"("creatorId", "status", "updatedAt");
CREATE INDEX "SupportTicket_status_updatedAt_idx" ON "SupportTicket"("status", "updatedAt");
CREATE INDEX "SupportMessage_ticketId_createdAt_idx" ON "SupportMessage"("ticketId", "createdAt");
CREATE INDEX "SupportMessage_authorId_createdAt_idx" ON "SupportMessage"("authorId", "createdAt");

ALTER TABLE "SupportTicket" ADD CONSTRAINT "SupportTicket_creatorId_fkey"
  FOREIGN KEY ("creatorId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "SupportTicket" ADD CONSTRAINT "SupportTicket_assignedToId_fkey"
  FOREIGN KEY ("assignedToId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "SupportTicket" ADD CONSTRAINT "SupportTicket_attachmentAssetId_fkey"
  FOREIGN KEY ("attachmentAssetId") REFERENCES "FileAsset"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "SupportMessage" ADD CONSTRAINT "SupportMessage_ticketId_fkey"
  FOREIGN KEY ("ticketId") REFERENCES "SupportTicket"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "SupportMessage" ADD CONSTRAINT "SupportMessage_authorId_fkey"
  FOREIGN KEY ("authorId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
