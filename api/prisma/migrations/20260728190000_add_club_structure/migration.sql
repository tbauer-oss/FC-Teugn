-- Extend the existing role enum without invalidating existing sessions or users.
ALTER TYPE "Role" ADD VALUE IF NOT EXISTS 'SUPER_ADMIN';
ALTER TYPE "Role" ADD VALUE IF NOT EXISTS 'CLUB_ADMIN';
ALTER TYPE "Role" ADD VALUE IF NOT EXISTS 'YOUTH_DIRECTOR';
ALTER TYPE "Role" ADD VALUE IF NOT EXISTS 'COACH';
ALTER TYPE "Role" ADD VALUE IF NOT EXISTS 'ASSISTANT_COACH';
ALTER TYPE "Role" ADD VALUE IF NOT EXISTS 'TEAM_MANAGER';
ALTER TYPE "Role" ADD VALUE IF NOT EXISTS 'PLAYER';
ALTER TYPE "Role" ADD VALUE IF NOT EXISTS 'READ_ONLY';

CREATE TABLE "Club" (
  "id" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "shortName" TEXT NOT NULL,
  "primaryColor" TEXT NOT NULL DEFAULT '#176B87',
  "accentColor" TEXT NOT NULL DEFAULT '#FFB000',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "Club_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "Season" (
  "id" TEXT NOT NULL,
  "clubId" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "startDate" TIMESTAMP(3) NOT NULL,
  "endDate" TIMESTAMP(3) NOT NULL,
  "isActive" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "Season_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "AgeGroup" (
  "id" TEXT NOT NULL,
  "seasonId" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "code" TEXT NOT NULL,
  "sortOrder" INTEGER NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "AgeGroup_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "Team" ADD COLUMN "ageGroupId" TEXT;
ALTER TABLE "Team" ADD COLUMN "shortName" TEXT;
ALTER TABLE "Team" ADD COLUMN "level" TEXT;
ALTER TABLE "Team" ADD COLUMN "isActive" BOOLEAN NOT NULL DEFAULT true;

INSERT INTO "Club" (
  "id", "name", "shortName", "primaryColor", "accentColor", "updatedAt"
) VALUES (
  'club-fc-teugn', 'FC Teugn', 'FCT', '#176B87', '#FFB000', CURRENT_TIMESTAMP
);

INSERT INTO "Season" (
  "id", "clubId", "name", "startDate", "endDate", "isActive", "updatedAt"
) VALUES (
  'season-2026-2027',
  'club-fc-teugn',
  '2026/27',
  TIMESTAMP '2026-07-01 00:00:00',
  TIMESTAMP '2027-06-30 23:59:59',
  true,
  CURRENT_TIMESTAMP
);

INSERT INTO "AgeGroup" (
  "id", "seasonId", "name", "code", "sortOrder", "updatedAt"
) VALUES
  ('agegroup-g-jugend-2026', 'season-2026-2027', 'G-Jugend', 'G', 10, CURRENT_TIMESTAMP),
  ('agegroup-f-jugend-2026', 'season-2026-2027', 'F-Jugend', 'F', 20, CURRENT_TIMESTAMP),
  ('agegroup-e-jugend-2026', 'season-2026-2027', 'E-Jugend', 'E', 30, CURRENT_TIMESTAMP),
  ('agegroup-d-jugend-2026', 'season-2026-2027', 'D-Jugend', 'D', 40, CURRENT_TIMESTAMP),
  ('agegroup-c-jugend-2026', 'season-2026-2027', 'C-Jugend', 'C', 50, CURRENT_TIMESTAMP),
  ('agegroup-b-jugend-2026', 'season-2026-2027', 'B-Jugend', 'B', 60, CURRENT_TIMESTAMP),
  ('agegroup-a-jugend-2026', 'season-2026-2027', 'A-Jugend', 'A', 70, CURRENT_TIMESTAMP);

UPDATE "Team"
SET
  "ageGroupId" = 'agegroup-e-jugend-2026',
  "shortName" = COALESCE("shortName", "name");

ALTER TABLE "Team" ALTER COLUMN "ageGroupId" SET NOT NULL;

CREATE TABLE "TeamMembership" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "teamId" TEXT NOT NULL,
  "role" "Role" NOT NULL,
  "status" "AccountStatus" NOT NULL DEFAULT 'PENDING',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "TeamMembership_pkey" PRIMARY KEY ("id")
);

INSERT INTO "TeamMembership" (
  "id", "userId", "teamId", "role", "status", "createdAt", "updatedAt"
)
SELECT
  'membership-' || "id",
  "id",
  "teamId",
  "role",
  "status",
  "createdAt",
  CURRENT_TIMESTAMP
FROM "User";

CREATE TABLE "AuditLog" (
  "id" TEXT NOT NULL,
  "actorId" TEXT,
  "teamId" TEXT,
  "action" TEXT NOT NULL,
  "entityType" TEXT NOT NULL,
  "entityId" TEXT,
  "metadata" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "AuditLog_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "Club_name_key" ON "Club"("name");
CREATE UNIQUE INDEX "Season_clubId_name_key" ON "Season"("clubId", "name");
CREATE INDEX "Season_clubId_isActive_idx" ON "Season"("clubId", "isActive");
CREATE UNIQUE INDEX "AgeGroup_seasonId_code_key" ON "AgeGroup"("seasonId", "code");
CREATE INDEX "AgeGroup_seasonId_sortOrder_idx" ON "AgeGroup"("seasonId", "sortOrder");
CREATE INDEX "Team_ageGroupId_isActive_idx" ON "Team"("ageGroupId", "isActive");
CREATE UNIQUE INDEX "TeamMembership_userId_teamId_key" ON "TeamMembership"("userId", "teamId");
CREATE INDEX "TeamMembership_teamId_status_idx" ON "TeamMembership"("teamId", "status");
CREATE INDEX "AuditLog_teamId_createdAt_idx" ON "AuditLog"("teamId", "createdAt");
CREATE INDEX "AuditLog_actorId_createdAt_idx" ON "AuditLog"("actorId", "createdAt");

ALTER TABLE "Season"
  ADD CONSTRAINT "Season_clubId_fkey"
  FOREIGN KEY ("clubId") REFERENCES "Club"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "AgeGroup"
  ADD CONSTRAINT "AgeGroup_seasonId_fkey"
  FOREIGN KEY ("seasonId") REFERENCES "Season"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "Team"
  ADD CONSTRAINT "Team_ageGroupId_fkey"
  FOREIGN KEY ("ageGroupId") REFERENCES "AgeGroup"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "TeamMembership"
  ADD CONSTRAINT "TeamMembership_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "TeamMembership"
  ADD CONSTRAINT "TeamMembership_teamId_fkey"
  FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "AuditLog"
  ADD CONSTRAINT "AuditLog_actorId_fkey"
  FOREIGN KEY ("actorId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "AuditLog"
  ADD CONSTRAINT "AuditLog_teamId_fkey"
  FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE SET NULL ON UPDATE CASCADE;
