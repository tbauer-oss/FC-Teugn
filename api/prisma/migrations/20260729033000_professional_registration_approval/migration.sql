ALTER TYPE "AccountStatus" ADD VALUE IF NOT EXISTS 'REJECTED';
ALTER TYPE "AccountStatus" ADD VALUE IF NOT EXISTS 'ARCHIVED';

CREATE TYPE "RegistrationReviewStatus" AS ENUM ('NEW', 'IN_REVIEW', 'NEEDS_INFO', 'COMPLETED');
CREATE TYPE "ConsentDocumentType" AS ENUM ('PRIVACY_POLICY', 'TERMS_OF_USE', 'PUSH_NOTIFICATIONS');

ALTER TABLE "User"
ADD COLUMN "firstName" TEXT,
ADD COLUMN "lastName" TEXT;

UPDATE "User"
SET
  "firstName" = CASE
    WHEN position(' ' IN trim("name")) > 0
      THEN split_part(trim("name"), ' ', 1)
    ELSE trim("name")
  END,
  "lastName" = CASE
    WHEN position(' ' IN trim("name")) > 0
      THEN trim(substr(trim("name"), position(' ' IN trim("name")) + 1))
    ELSE ''
  END
WHERE "firstName" IS NULL;

CREATE TABLE "ConsentTextVersion" (
  "id" TEXT NOT NULL,
  "type" "ConsentDocumentType" NOT NULL,
  "version" INTEGER NOT NULL,
  "title" TEXT NOT NULL,
  "content" TEXT NOT NULL,
  "checksum" TEXT NOT NULL,
  "isActive" BOOLEAN NOT NULL DEFAULT false,
  "publishedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ConsentTextVersion_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "UserConsent" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "consentTextVersionId" TEXT NOT NULL,
  "granted" BOOLEAN NOT NULL,
  "grantedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "revokedAt" TIMESTAMP(3),
  "source" TEXT NOT NULL DEFAULT 'REGISTRATION',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "UserConsent_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "RegistrationRequest" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "requestedRole" "Role" NOT NULL,
  "childName" TEXT,
  "relationship" "GuardianRelationship",
  "reviewStatus" "RegistrationReviewStatus" NOT NULL DEFAULT 'NEW',
  "adminNote" TEXT,
  "applicantMessage" TEXT,
  "reviewedById" TEXT,
  "reviewedAt" TIMESTAMP(3),
  "pushOptIn" BOOLEAN NOT NULL DEFAULT false,
  "privacyAcceptedAt" TIMESTAMP(3) NOT NULL,
  "termsAcceptedAt" TIMESTAMP(3) NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "RegistrationRequest_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "RegistrationTeamRequest" (
  "id" TEXT NOT NULL,
  "registrationRequestId" TEXT NOT NULL,
  "teamId" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "RegistrationTeamRequest_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "RegistrationHistory" (
  "id" TEXT NOT NULL,
  "registrationRequestId" TEXT NOT NULL,
  "actorId" TEXT,
  "fromStatus" "AccountStatus",
  "toStatus" "AccountStatus",
  "fromReviewStatus" "RegistrationReviewStatus",
  "toReviewStatus" "RegistrationReviewStatus",
  "note" TEXT,
  "metadata" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "RegistrationHistory_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "ConsentTextVersion_type_version_key" ON "ConsentTextVersion"("type", "version");
CREATE INDEX "ConsentTextVersion_type_isActive_idx" ON "ConsentTextVersion"("type", "isActive");
CREATE UNIQUE INDEX "UserConsent_userId_consentTextVersionId_key" ON "UserConsent"("userId", "consentTextVersionId");
CREATE INDEX "UserConsent_userId_granted_idx" ON "UserConsent"("userId", "granted");
CREATE UNIQUE INDEX "RegistrationRequest_userId_key" ON "RegistrationRequest"("userId");
CREATE INDEX "RegistrationRequest_reviewStatus_createdAt_idx" ON "RegistrationRequest"("reviewStatus", "createdAt");
CREATE UNIQUE INDEX "RegistrationTeamRequest_registrationRequestId_teamId_key" ON "RegistrationTeamRequest"("registrationRequestId", "teamId");
CREATE INDEX "RegistrationTeamRequest_teamId_idx" ON "RegistrationTeamRequest"("teamId");
CREATE INDEX "RegistrationHistory_registrationRequestId_createdAt_idx" ON "RegistrationHistory"("registrationRequestId", "createdAt");

ALTER TABLE "UserConsent"
ADD CONSTRAINT "UserConsent_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE,
ADD CONSTRAINT "UserConsent_consentTextVersionId_fkey" FOREIGN KEY ("consentTextVersionId") REFERENCES "ConsentTextVersion"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "RegistrationRequest"
ADD CONSTRAINT "RegistrationRequest_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE,
ADD CONSTRAINT "RegistrationRequest_reviewedById_fkey" FOREIGN KEY ("reviewedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "RegistrationTeamRequest"
ADD CONSTRAINT "RegistrationTeamRequest_registrationRequestId_fkey" FOREIGN KEY ("registrationRequestId") REFERENCES "RegistrationRequest"("id") ON DELETE CASCADE ON UPDATE CASCADE,
ADD CONSTRAINT "RegistrationTeamRequest_teamId_fkey" FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "RegistrationHistory"
ADD CONSTRAINT "RegistrationHistory_registrationRequestId_fkey" FOREIGN KEY ("registrationRequestId") REFERENCES "RegistrationRequest"("id") ON DELETE CASCADE ON UPDATE CASCADE,
ADD CONSTRAINT "RegistrationHistory_actorId_fkey" FOREIGN KEY ("actorId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

INSERT INTO "ConsentTextVersion" ("id", "type", "version", "title", "content", "checksum", "isActive")
VALUES
  ('consent_privacy_v1', 'PRIVACY_POLICY', 1, 'Datenschutzinformation', 'Datenschutzinformation für die Nutzung der FC-Teugn-App und die Verarbeitung von Vereins- und Mannschaftsdaten.', md5('FC-Teugn Datenschutz v1'), true),
  ('consent_terms_v1', 'TERMS_OF_USE', 1, 'Nutzungsbedingungen', 'Nutzungsbedingungen für Mitglieder, Sorgeberechtigte, Spieler und Funktionsträger des FC Teugn.', md5('FC-Teugn Nutzungsbedingungen v1'), true),
  ('consent_push_v1', 'PUSH_NOTIFICATIONS', 1, 'Push-Mitteilungen', 'Optionale Einwilligung in Push-Mitteilungen zu Mannschaftsterminen und wichtigen Vereinsinformationen.', md5('FC-Teugn Push v1'), true)
ON CONFLICT ("type", "version") DO NOTHING;
