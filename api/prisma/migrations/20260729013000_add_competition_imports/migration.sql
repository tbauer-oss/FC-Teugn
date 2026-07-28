CREATE TYPE "ImportFormat" AS ENUM ('CSV', 'ICS');
CREATE TYPE "ImportJobStatus" AS ENUM ('PREVIEWED', 'APPLIED', 'FAILED');
CREATE TYPE "ImportRowAction" AS ENUM (
  'CREATE', 'UPDATE', 'SKIP', 'CONFLICT', 'INVALID'
);

CREATE TABLE "ImportJob" (
  "id" TEXT NOT NULL,
  "actorId" TEXT NOT NULL,
  "teamId" TEXT NOT NULL,
  "format" "ImportFormat" NOT NULL,
  "provider" TEXT NOT NULL,
  "fileName" TEXT,
  "status" "ImportJobStatus" NOT NULL DEFAULT 'PREVIEWED',
  "sourceHash" TEXT NOT NULL,
  "totalRows" INTEGER NOT NULL DEFAULT 0,
  "createCount" INTEGER NOT NULL DEFAULT 0,
  "updateCount" INTEGER NOT NULL DEFAULT 0,
  "skipCount" INTEGER NOT NULL DEFAULT 0,
  "conflictCount" INTEGER NOT NULL DEFAULT 0,
  "invalidCount" INTEGER NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "appliedAt" TIMESTAMP(3),
  CONSTRAINT "ImportJob_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "ImportJob_teamId_createdAt_idx" ON "ImportJob"("teamId", "createdAt");
CREATE INDEX "ImportJob_actorId_createdAt_idx" ON "ImportJob"("actorId", "createdAt");
ALTER TABLE "ImportJob" ADD CONSTRAINT "ImportJob_actorId_fkey"
  FOREIGN KEY ("actorId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "ImportJob" ADD CONSTRAINT "ImportJob_teamId_fkey"
  FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE TABLE "ImportRow" (
  "id" TEXT NOT NULL,
  "jobId" TEXT NOT NULL,
  "rowNumber" INTEGER NOT NULL,
  "externalId" TEXT,
  "action" "ImportRowAction" NOT NULL,
  "normalized" JSONB,
  "messages" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  "entityId" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ImportRow_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "ImportRow_jobId_rowNumber_key" ON "ImportRow"("jobId", "rowNumber");
CREATE INDEX "ImportRow_jobId_action_idx" ON "ImportRow"("jobId", "action");
ALTER TABLE "ImportRow" ADD CONSTRAINT "ImportRow_jobId_fkey"
  FOREIGN KEY ("jobId") REFERENCES "ImportJob"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "ExternalReference" (
  "id" TEXT NOT NULL,
  "teamId" TEXT NOT NULL,
  "provider" TEXT NOT NULL,
  "entityType" TEXT NOT NULL,
  "externalId" TEXT NOT NULL,
  "entityId" TEXT NOT NULL,
  "sourceChecksum" TEXT NOT NULL,
  "sourceUrl" TEXT,
  "lastSyncedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "ExternalReference_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "ExternalReference_provider_entityType_externalId_key"
  ON "ExternalReference"("provider", "entityType", "externalId");
CREATE INDEX "ExternalReference_teamId_entityType_idx"
  ON "ExternalReference"("teamId", "entityType");
CREATE INDEX "ExternalReference_entityId_idx" ON "ExternalReference"("entityId");
ALTER TABLE "ExternalReference" ADD CONSTRAINT "ExternalReference_teamId_fkey"
  FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
