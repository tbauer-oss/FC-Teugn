ALTER TABLE "Team"
ADD COLUMN "seasonStartDate" TIMESTAMP(3),
ADD COLUMN "seasonEndDate" TIMESTAMP(3),
ADD COLUMN "indoorSeasonStartDate" TIMESTAMP(3),
ADD COLUMN "indoorSeasonEndDate" TIMESTAMP(3),
ADD COLUMN "indoorTrainingLocation" TEXT,
ADD COLUMN "indoorTrainingTimes" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
ADD COLUMN "indoorTrainingPartnerIds" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];
