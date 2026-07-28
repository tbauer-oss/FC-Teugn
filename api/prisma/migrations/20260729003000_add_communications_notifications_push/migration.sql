CREATE TYPE "AnnouncementPriority" AS ENUM ('NORMAL', 'IMPORTANT', 'URGENT');
CREATE TYPE "AnnouncementAudience" AS ENUM (
  'ALL_MEMBERS', 'PARENTS', 'PLAYERS', 'STAFF', 'INDIVIDUALS'
);
CREATE TYPE "AnnouncementStatus" AS ENUM (
  'DRAFT', 'SCHEDULED', 'PUBLISHED', 'ARCHIVED'
);
CREATE TYPE "NotificationCategory" AS ENUM (
  'EVENT', 'EVENT_REMINDER', 'ANNOUNCEMENT', 'NOMINATION', 'LINEUP',
  'LIVE_TICKER', 'MATCH', 'REGISTRATION', 'URGENT', 'SYSTEM'
);
CREATE TYPE "NotificationDeliveryStatus" AS ENUM (
  'PENDING', 'SENT', 'FAILED', 'SKIPPED'
);
CREATE TYPE "PushPlatform" AS ENUM ('WEB', 'ANDROID');

CREATE TABLE "Announcement" (
  "id" TEXT NOT NULL,
  "authorId" TEXT NOT NULL,
  "title" TEXT NOT NULL,
  "body" TEXT NOT NULL,
  "audience" "AnnouncementAudience" NOT NULL DEFAULT 'ALL_MEMBERS',
  "priority" "AnnouncementPriority" NOT NULL DEFAULT 'NORMAL',
  "status" "AnnouncementStatus" NOT NULL DEFAULT 'DRAFT',
  "publishAt" TIMESTAMP(3),
  "expiresAt" TIMESTAMP(3),
  "requireReadReceipt" BOOLEAN NOT NULL DEFAULT false,
  "pushEnabled" BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  "publishedAt" TIMESTAMP(3),
  "archivedAt" TIMESTAMP(3),
  CONSTRAINT "Announcement_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "Announcement_status_publishAt_expiresAt_idx"
  ON "Announcement"("status", "publishAt", "expiresAt");
CREATE INDEX "Announcement_authorId_createdAt_idx"
  ON "Announcement"("authorId", "createdAt");
ALTER TABLE "Announcement"
  ADD CONSTRAINT "Announcement_authorId_fkey"
  FOREIGN KEY ("authorId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE TABLE "AnnouncementTargetTeam" (
  "id" TEXT NOT NULL,
  "announcementId" TEXT NOT NULL,
  "teamId" TEXT NOT NULL,
  CONSTRAINT "AnnouncementTargetTeam_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "AnnouncementTargetTeam_announcementId_teamId_key"
  ON "AnnouncementTargetTeam"("announcementId", "teamId");
CREATE INDEX "AnnouncementTargetTeam_teamId_announcementId_idx"
  ON "AnnouncementTargetTeam"("teamId", "announcementId");
ALTER TABLE "AnnouncementTargetTeam"
  ADD CONSTRAINT "AnnouncementTargetTeam_announcementId_fkey"
  FOREIGN KEY ("announcementId") REFERENCES "Announcement"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "AnnouncementTargetTeam"
  ADD CONSTRAINT "AnnouncementTargetTeam_teamId_fkey"
  FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "AnnouncementRecipient" (
  "id" TEXT NOT NULL,
  "announcementId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  CONSTRAINT "AnnouncementRecipient_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "AnnouncementRecipient_announcementId_userId_key"
  ON "AnnouncementRecipient"("announcementId", "userId");
CREATE INDEX "AnnouncementRecipient_userId_announcementId_idx"
  ON "AnnouncementRecipient"("userId", "announcementId");
ALTER TABLE "AnnouncementRecipient"
  ADD CONSTRAINT "AnnouncementRecipient_announcementId_fkey"
  FOREIGN KEY ("announcementId") REFERENCES "Announcement"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "AnnouncementRecipient"
  ADD CONSTRAINT "AnnouncementRecipient_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "AnnouncementAttachment" (
  "id" TEXT NOT NULL,
  "announcementId" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "url" TEXT NOT NULL,
  "mimeType" TEXT,
  "sizeBytes" INTEGER,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "AnnouncementAttachment_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "AnnouncementAttachment_announcementId_idx"
  ON "AnnouncementAttachment"("announcementId");
ALTER TABLE "AnnouncementAttachment"
  ADD CONSTRAINT "AnnouncementAttachment_announcementId_fkey"
  FOREIGN KEY ("announcementId") REFERENCES "Announcement"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "AnnouncementRead" (
  "id" TEXT NOT NULL,
  "announcementId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "readAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "AnnouncementRead_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "AnnouncementRead_announcementId_userId_key"
  ON "AnnouncementRead"("announcementId", "userId");
CREATE INDEX "AnnouncementRead_userId_readAt_idx"
  ON "AnnouncementRead"("userId", "readAt");
ALTER TABLE "AnnouncementRead"
  ADD CONSTRAINT "AnnouncementRead_announcementId_fkey"
  FOREIGN KEY ("announcementId") REFERENCES "Announcement"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "AnnouncementRead"
  ADD CONSTRAINT "AnnouncementRead_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "Notification" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "category" "NotificationCategory" NOT NULL,
  "title" TEXT NOT NULL,
  "body" TEXT NOT NULL,
  "actionUrl" TEXT,
  "entityType" TEXT,
  "entityId" TEXT,
  "readAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "expiresAt" TIMESTAMP(3),
  CONSTRAINT "Notification_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "Notification_userId_readAt_createdAt_idx"
  ON "Notification"("userId", "readAt", "createdAt");
ALTER TABLE "Notification"
  ADD CONSTRAINT "Notification_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "PushSubscription" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "platform" "PushPlatform" NOT NULL,
  "endpoint" TEXT NOT NULL,
  "p256dh" TEXT,
  "auth" TEXT,
  "deviceName" TEXT,
  "isActive" BOOLEAN NOT NULL DEFAULT true,
  "lastUsedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "PushSubscription_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "PushSubscription_endpoint_key" ON "PushSubscription"("endpoint");
CREATE INDEX "PushSubscription_userId_isActive_idx"
  ON "PushSubscription"("userId", "isActive");
ALTER TABLE "PushSubscription"
  ADD CONSTRAINT "PushSubscription_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "NotificationPreference" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "category" "NotificationCategory" NOT NULL,
  "inApp" BOOLEAN NOT NULL DEFAULT true,
  "push" BOOLEAN NOT NULL DEFAULT true,
  CONSTRAINT "NotificationPreference_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "NotificationPreference_userId_category_key"
  ON "NotificationPreference"("userId", "category");
ALTER TABLE "NotificationPreference"
  ADD CONSTRAINT "NotificationPreference_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "NotificationDelivery" (
  "id" TEXT NOT NULL,
  "notificationId" TEXT NOT NULL,
  "subscriptionId" TEXT,
  "userId" TEXT NOT NULL,
  "status" "NotificationDeliveryStatus" NOT NULL DEFAULT 'PENDING',
  "attemptCount" INTEGER NOT NULL DEFAULT 0,
  "lastAttemptAt" TIMESTAMP(3),
  "sentAt" TIMESTAMP(3),
  "errorCode" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "NotificationDelivery_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "NotificationDelivery_status_createdAt_idx"
  ON "NotificationDelivery"("status", "createdAt");
CREATE INDEX "NotificationDelivery_userId_createdAt_idx"
  ON "NotificationDelivery"("userId", "createdAt");
ALTER TABLE "NotificationDelivery"
  ADD CONSTRAINT "NotificationDelivery_notificationId_fkey"
  FOREIGN KEY ("notificationId") REFERENCES "Notification"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "NotificationDelivery"
  ADD CONSTRAINT "NotificationDelivery_subscriptionId_fkey"
  FOREIGN KEY ("subscriptionId") REFERENCES "PushSubscription"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "NotificationDelivery"
  ADD CONSTRAINT "NotificationDelivery_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
