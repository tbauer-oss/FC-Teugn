ALTER TABLE "IndoorOccupancyEntry"
ADD COLUMN "isRecurring" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "recurrenceWeekdays" INTEGER[] NOT NULL DEFAULT ARRAY[]::INTEGER[],
ADD COLUMN "recurrenceIntervalWeeks" INTEGER NOT NULL DEFAULT 1,
ADD COLUMN "recurrenceUntil" TIMESTAMP(3);

ALTER TABLE "IndoorOccupancyEntry"
ALTER COLUMN "location" SET DEFAULT 'Sporthalle';

UPDATE "IndoorOccupancyEntry"
SET "location" = 'Sporthalle';

UPDATE "Team"
SET "indoorTrainingLocation" = 'Sporthalle'
WHERE "indoorTrainingLocation" IS NOT NULL
   OR cardinality("indoorTrainingTimes") > 0;
