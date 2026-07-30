ALTER TABLE "Team"
ADD COLUMN "trainingPartnerIds" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
ADD COLUMN "matchdayTimes" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

ALTER TABLE "Season"
ADD COLUMN "seniorTrainingLocation" TEXT,
ADD COLUMN "seniorTrainingTimes" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
ADD COLUMN "seniorMatchdayTimes" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
ADD COLUMN "approvedOccupancyConflictKeys" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];
