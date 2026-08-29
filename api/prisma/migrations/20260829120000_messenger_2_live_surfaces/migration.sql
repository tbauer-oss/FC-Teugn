ALTER TYPE "FileAssetKind" ADD VALUE IF NOT EXISTS 'FAMILY_CONTACT_ATTACHMENT';

ALTER TABLE "Notification"
ADD COLUMN IF NOT EXISTS "metadata" JSONB;

CREATE TABLE IF NOT EXISTS "FamilyContactAttachment" (
  "id" TEXT NOT NULL,
  "messageId" TEXT NOT NULL,
  "conversationId" TEXT NOT NULL,
  "teamId" TEXT,
  "uploadedById" TEXT NOT NULL,
  "fileAssetId" TEXT NOT NULL,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "FamilyContactAttachment_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "FamilyContactAttachment_messageId_key"
ON "FamilyContactAttachment"("messageId");
CREATE UNIQUE INDEX IF NOT EXISTS "FamilyContactAttachment_fileAssetId_key"
ON "FamilyContactAttachment"("fileAssetId");
CREATE INDEX IF NOT EXISTS "FamilyContactAttachment_conversationId_createdAt_idx"
ON "FamilyContactAttachment"("conversationId", "createdAt");
CREATE INDEX IF NOT EXISTS "FamilyContactAttachment_expiresAt_idx"
ON "FamilyContactAttachment"("expiresAt");

ALTER TABLE "FamilyContactAttachment"
ADD CONSTRAINT "FamilyContactAttachment_teamId_fkey"
FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "FamilyContactAttachment"
ADD CONSTRAINT "FamilyContactAttachment_uploadedById_fkey"
FOREIGN KEY ("uploadedById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "FamilyContactAttachment"
ADD CONSTRAINT "FamilyContactAttachment_fileAssetId_fkey"
FOREIGN KEY ("fileAssetId") REFERENCES "FileAsset"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
