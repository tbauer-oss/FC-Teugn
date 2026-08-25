CREATE TABLE "RegularTrainingAttendancePreference" (
    "id" TEXT NOT NULL,
    "playerId" TEXT NOT NULL,
    "teamId" TEXT NOT NULL,
    "respondedById" TEXT NOT NULL,
    "validFrom" TIMESTAMP(3) NOT NULL,
    "validUntil" TIMESTAMP(3) NOT NULL,
    "status" "AttendanceStatus" NOT NULL DEFAULT 'YES',
    "responseSource" "AttendanceResponseSource" NOT NULL,
    "responderRelationship" "GuardianRelationship",
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "RegularTrainingAttendancePreference_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "RegularTrainingAttendancePreference_playerId_teamId_key"
ON "RegularTrainingAttendancePreference"("playerId", "teamId");

CREATE INDEX "RegularTrainingAttendancePreference_teamId_validFrom_validUntil_idx"
ON "RegularTrainingAttendancePreference"("teamId", "validFrom", "validUntil");

ALTER TABLE "RegularTrainingAttendancePreference"
ADD CONSTRAINT "RegularTrainingAttendancePreference_playerId_fkey"
FOREIGN KEY ("playerId") REFERENCES "Player"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "RegularTrainingAttendancePreference"
ADD CONSTRAINT "RegularTrainingAttendancePreference_teamId_fkey"
FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "RegularTrainingAttendancePreference"
ADD CONSTRAINT "RegularTrainingAttendancePreference_respondedById_fkey"
FOREIGN KEY ("respondedById") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
