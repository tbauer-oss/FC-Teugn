ALTER TABLE "Season"
ADD COLUMN "recreationalTrainingLocation" TEXT,
ADD COLUMN "recreationalTrainingTimes" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];
