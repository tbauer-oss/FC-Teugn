CREATE TYPE "TrainingPhase" AS ENUM (
  'WARM_UP', 'MAIN_PART', 'GAME_FORM', 'COOL_DOWN'
);
CREATE TYPE "TrainingAttendanceStatus" AS ENUM (
  'PRESENT', 'EXCUSED', 'UNEXCUSED', 'INJURED', 'LATE', 'LEFT_EARLY'
);
ALTER TABLE "Attendance" ADD COLUMN "trainingStatus" "TrainingAttendanceStatus";
UPDATE "Attendance"
SET "trainingStatus" = CASE
  WHEN "actualAttendance" = 'YES' THEN 'PRESENT'::"TrainingAttendanceStatus"
  WHEN "actualAttendance" = 'NO' THEN 'EXCUSED'::"TrainingAttendanceStatus"
  ELSE NULL
END
WHERE "actualAttendance" IS NOT NULL;

CREATE TABLE "TeamMatchStatistic" (
  "id" TEXT NOT NULL,
  "eventId" TEXT NOT NULL,
  "ourGoals" INTEGER NOT NULL,
  "theirGoals" INTEGER NOT NULL,
  "result" TEXT NOT NULL,
  "isHome" BOOLEAN NOT NULL,
  "recalculatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "TeamMatchStatistic_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "TeamMatchStatistic_eventId_key"
  ON "TeamMatchStatistic"("eventId");
ALTER TABLE "TeamMatchStatistic"
  ADD CONSTRAINT "TeamMatchStatistic_eventId_fkey"
  FOREIGN KEY ("eventId") REFERENCES "Event"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "PlayerMatchStatistic" (
  "id" TEXT NOT NULL,
  "eventId" TEXT NOT NULL,
  "playerId" TEXT NOT NULL,
  "appeared" BOOLEAN NOT NULL DEFAULT false,
  "started" BOOLEAN NOT NULL DEFAULT false,
  "minutesPlayed" INTEGER NOT NULL DEFAULT 0,
  "goals" INTEGER NOT NULL DEFAULT 0,
  "assists" INTEGER NOT NULL DEFAULT 0,
  "isGoalkeeper" BOOLEAN NOT NULL DEFAULT false,
  "isCaptain" BOOLEAN NOT NULL DEFAULT false,
  "recalculatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "PlayerMatchStatistic_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "PlayerMatchStatistic_eventId_playerId_key"
  ON "PlayerMatchStatistic"("eventId", "playerId");
CREATE INDEX "PlayerMatchStatistic_playerId_recalculatedAt_idx"
  ON "PlayerMatchStatistic"("playerId", "recalculatedAt");
ALTER TABLE "PlayerMatchStatistic"
  ADD CONSTRAINT "PlayerMatchStatistic_eventId_fkey"
  FOREIGN KEY ("eventId") REFERENCES "Event"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PlayerMatchStatistic"
  ADD CONSTRAINT "PlayerMatchStatistic_playerId_fkey"
  FOREIGN KEY ("playerId") REFERENCES "Player"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE TABLE "TrainingPlan" (
  "id" TEXT NOT NULL,
  "eventId" TEXT NOT NULL,
  "createdById" TEXT NOT NULL,
  "focusAreas" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  "learningGoals" TEXT,
  "durationMinutes" INTEGER NOT NULL,
  "participantNotes" TEXT,
  "coaches" TEXT,
  "materials" TEXT,
  "pitchSetup" TEXT,
  "feedback" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "TrainingPlan_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "TrainingPlan_eventId_key" ON "TrainingPlan"("eventId");
ALTER TABLE "TrainingPlan"
  ADD CONSTRAINT "TrainingPlan_eventId_fkey"
  FOREIGN KEY ("eventId") REFERENCES "Event"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "TrainingPlan"
  ADD CONSTRAINT "TrainingPlan_createdById_fkey"
  FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE TABLE "TrainingExercise" (
  "id" TEXT NOT NULL,
  "teamId" TEXT NOT NULL,
  "createdById" TEXT NOT NULL,
  "title" TEXT NOT NULL,
  "category" TEXT NOT NULL,
  "ageGroups" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  "minPlayers" INTEGER,
  "maxPlayers" INTEGER,
  "durationMinutes" INTEGER NOT NULL,
  "materials" TEXT,
  "setup" TEXT NOT NULL,
  "instructions" TEXT NOT NULL,
  "coachingPoints" TEXT,
  "variations" TEXT,
  "diagramUrl" TEXT,
  "isFavorite" BOOLEAN NOT NULL DEFAULT false,
  "isArchived" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "TrainingExercise_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "TrainingExercise_teamId_category_isArchived_idx"
  ON "TrainingExercise"("teamId", "category", "isArchived");
ALTER TABLE "TrainingExercise"
  ADD CONSTRAINT "TrainingExercise_teamId_fkey"
  FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "TrainingExercise"
  ADD CONSTRAINT "TrainingExercise_createdById_fkey"
  FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE TABLE "TrainingPlanItem" (
  "id" TEXT NOT NULL,
  "trainingPlanId" TEXT NOT NULL,
  "exerciseId" TEXT,
  "phase" "TrainingPhase" NOT NULL,
  "title" TEXT NOT NULL,
  "durationMinutes" INTEGER NOT NULL,
  "position" INTEGER NOT NULL,
  "notes" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "TrainingPlanItem_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "TrainingPlanItem_trainingPlanId_position_key"
  ON "TrainingPlanItem"("trainingPlanId", "position");
CREATE INDEX "TrainingPlanItem_trainingPlanId_phase_idx"
  ON "TrainingPlanItem"("trainingPlanId", "phase");
ALTER TABLE "TrainingPlanItem"
  ADD CONSTRAINT "TrainingPlanItem_trainingPlanId_fkey"
  FOREIGN KEY ("trainingPlanId") REFERENCES "TrainingPlan"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "TrainingPlanItem"
  ADD CONSTRAINT "TrainingPlanItem_exerciseId_fkey"
  FOREIGN KEY ("exerciseId") REFERENCES "TrainingExercise"("id") ON DELETE SET NULL ON UPDATE CASCADE;
