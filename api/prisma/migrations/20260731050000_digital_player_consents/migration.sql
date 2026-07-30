ALTER TABLE "PlayerConsent"
  ADD COLUMN "templateVersion" TEXT,
  ADD COLUMN "currentHash" TEXT;

CREATE TABLE "PlayerConsentEvidence" (
  "id" TEXT NOT NULL,
  "consentId" TEXT NOT NULL,
  "signerId" TEXT NOT NULL,
  "action" "ConsentStatus" NOT NULL,
  "templateVersion" TEXT NOT NULL,
  "statement" JSONB NOT NULL,
  "signatureData" JSONB,
  "signerName" TEXT NOT NULL,
  "signerRole" TEXT NOT NULL,
  "guardianAuthorityConfirmed" BOOLEAN NOT NULL DEFAULT false,
  "childAssentName" TEXT,
  "documentHash" TEXT NOT NULL,
  "clientSignedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "PlayerConsentEvidence_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "PlayerConsentEvidence_documentHash_key"
  ON "PlayerConsentEvidence"("documentHash");
CREATE INDEX "PlayerConsentEvidence_consentId_createdAt_idx"
  ON "PlayerConsentEvidence"("consentId", "createdAt");
CREATE INDEX "PlayerConsentEvidence_signerId_createdAt_idx"
  ON "PlayerConsentEvidence"("signerId", "createdAt");

ALTER TABLE "PlayerConsentEvidence"
  ADD CONSTRAINT "PlayerConsentEvidence_consentId_fkey"
  FOREIGN KEY ("consentId") REFERENCES "PlayerConsent"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PlayerConsentEvidence"
  ADD CONSTRAINT "PlayerConsentEvidence_signerId_fkey"
  FOREIGN KEY ("signerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
