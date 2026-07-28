CREATE TYPE "PlayerStatus" AS ENUM ('ACTIVE', 'INJURED', 'PAUSED', 'LEFT');
CREATE TYPE "DominantFoot" AS ENUM ('RIGHT', 'LEFT', 'BOTH', 'UNKNOWN');
CREATE TYPE "GuardianRelationship" AS ENUM ('MOTHER', 'FATHER', 'GUARDIAN', 'OTHER');
CREATE TYPE "DevelopmentCategory" AS ENUM ('TECHNIQUE', 'TACTICS', 'ATHLETIC', 'SOCIAL', 'GOALKEEPING', 'GENERAL');
CREATE TYPE "NoteVisibility" AS ENUM ('STAFF_ONLY', 'GUARDIANS_AND_STAFF');
CREATE TYPE "ConsentType" AS ENUM ('PHOTO', 'TEAM_PHOTO', 'TRANSPORT', 'MEDICAL_DATA', 'COMMUNICATION');
CREATE TYPE "ConsentStatus" AS ENUM ('PENDING', 'GRANTED', 'REVOKED', 'EXPIRED');

ALTER TABLE "Player"
  ADD COLUMN "userId" TEXT,
  ADD COLUMN "preferredName" TEXT,
  ADD COLUMN "nationality" TEXT,
  ADD COLUMN "secondaryPosition" TEXT,
  ADD COLUMN "dominantFoot" "DominantFoot" NOT NULL DEFAULT 'UNKNOWN',
  ADD COLUMN "status" "PlayerStatus" NOT NULL DEFAULT 'ACTIVE',
  ADD COLUMN "joinedAt" TIMESTAMP(3),
  ADD COLUMN "photoUrl" TEXT;

ALTER TABLE "ParentPlayerLink"
  ADD COLUMN "relationship" "GuardianRelationship" NOT NULL DEFAULT 'GUARDIAN',
  ADD COLUMN "isLegalGuardian" BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN "canPickup" BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN "receivesCommunication" BOOLEAN NOT NULL DEFAULT true;

CREATE TABLE "PlayerMedicalProfile" (
  "id" TEXT NOT NULL,
  "playerId" TEXT NOT NULL,
  "allergies" TEXT,
  "medications" TEXT,
  "conditions" TEXT,
  "physicianName" TEXT,
  "physicianPhone" TEXT,
  "emergencyNotes" TEXT,
  "updatedById" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "PlayerMedicalProfile_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "PlayerEmergencyContact" (
  "id" TEXT NOT NULL,
  "playerId" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "relationship" TEXT,
  "phone" TEXT NOT NULL,
  "priority" INTEGER NOT NULL DEFAULT 1,
  "isAuthorizedPickup" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "PlayerEmergencyContact_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "PlayerDevelopmentNote" (
  "id" TEXT NOT NULL,
  "playerId" TEXT NOT NULL,
  "authorId" TEXT NOT NULL,
  "category" "DevelopmentCategory" NOT NULL DEFAULT 'GENERAL',
  "visibility" "NoteVisibility" NOT NULL DEFAULT 'STAFF_ONLY',
  "rating" INTEGER,
  "title" TEXT NOT NULL,
  "notes" TEXT NOT NULL,
  "observedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "PlayerDevelopmentNote_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "PlayerConsent" (
  "id" TEXT NOT NULL,
  "playerId" TEXT NOT NULL,
  "type" "ConsentType" NOT NULL,
  "status" "ConsentStatus" NOT NULL DEFAULT 'PENDING',
  "grantedBy" TEXT,
  "grantedAt" TIMESTAMP(3),
  "expiresAt" TIMESTAMP(3),
  "revokedAt" TIMESTAMP(3),
  "note" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "PlayerConsent_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "Player_teamId_status_lastName_idx" ON "Player"("teamId", "status", "lastName");
CREATE UNIQUE INDEX "Player_userId_key" ON "Player"("userId");
CREATE INDEX "ParentPlayerLink_playerId_idx" ON "ParentPlayerLink"("playerId");
CREATE UNIQUE INDEX "PlayerMedicalProfile_playerId_key" ON "PlayerMedicalProfile"("playerId");
CREATE INDEX "PlayerEmergencyContact_playerId_priority_idx" ON "PlayerEmergencyContact"("playerId", "priority");
CREATE INDEX "PlayerDevelopmentNote_playerId_observedAt_idx" ON "PlayerDevelopmentNote"("playerId", "observedAt");
CREATE UNIQUE INDEX "PlayerConsent_playerId_type_key" ON "PlayerConsent"("playerId", "type");
CREATE INDEX "PlayerConsent_playerId_status_idx" ON "PlayerConsent"("playerId", "status");

ALTER TABLE "PlayerMedicalProfile"
  ADD CONSTRAINT "PlayerMedicalProfile_playerId_fkey"
  FOREIGN KEY ("playerId") REFERENCES "Player"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "Player"
  ADD CONSTRAINT "Player_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "PlayerMedicalProfile"
  ADD CONSTRAINT "PlayerMedicalProfile_updatedById_fkey"
  FOREIGN KEY ("updatedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "PlayerEmergencyContact"
  ADD CONSTRAINT "PlayerEmergencyContact_playerId_fkey"
  FOREIGN KEY ("playerId") REFERENCES "Player"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PlayerDevelopmentNote"
  ADD CONSTRAINT "PlayerDevelopmentNote_playerId_fkey"
  FOREIGN KEY ("playerId") REFERENCES "Player"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PlayerDevelopmentNote"
  ADD CONSTRAINT "PlayerDevelopmentNote_authorId_fkey"
  FOREIGN KEY ("authorId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "PlayerConsent"
  ADD CONSTRAINT "PlayerConsent_playerId_fkey"
  FOREIGN KEY ("playerId") REFERENCES "Player"("id") ON DELETE CASCADE ON UPDATE CASCADE;
