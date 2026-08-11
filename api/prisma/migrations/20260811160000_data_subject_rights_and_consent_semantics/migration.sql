-- A privacy notice is acknowledged, contractual terms are agreed and only
-- optional processing is consented to. Keeping these records distinct avoids
-- treating every legal basis as revocable consent.
CREATE TYPE "ConsentRecordKind" AS ENUM ('ACKNOWLEDGEMENT', 'AGREEMENT', 'CONSENT');

ALTER TABLE "UserConsent"
ADD COLUMN "recordKind" "ConsentRecordKind" NOT NULL DEFAULT 'CONSENT';

UPDATE "UserConsent" AS uc
SET "recordKind" = CASE ctv."type"::text
  WHEN 'PRIVACY_POLICY' THEN 'ACKNOWLEDGEMENT'::"ConsentRecordKind"
  WHEN 'TERMS_OF_USE' THEN 'AGREEMENT'::"ConsentRecordKind"
  ELSE 'CONSENT'::"ConsentRecordKind"
END
FROM "ConsentTextVersion" AS ctv
WHERE ctv."id" = uc."consentTextVersionId";

ALTER TYPE "DataSubjectRequestType" ADD VALUE IF NOT EXISTS 'ACCESS';
ALTER TYPE "DataSubjectRequestType" ADD VALUE IF NOT EXISTS 'PORTABILITY';
ALTER TYPE "DataSubjectRequestType" ADD VALUE IF NOT EXISTS 'RESTRICTION';
ALTER TYPE "DataSubjectRequestType" ADD VALUE IF NOT EXISTS 'OBJECTION';
ALTER TYPE "DataSubjectRequestType" ADD VALUE IF NOT EXISTS 'CONSENT_WITHDRAWAL';
