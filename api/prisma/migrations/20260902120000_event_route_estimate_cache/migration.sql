ALTER TABLE "Event"
ADD COLUMN "routeEstimateAddress" TEXT,
ADD COLUMN "routeDistanceKm" DOUBLE PRECISION,
ADD COLUMN "routeDurationMinutes" INTEGER,
ADD COLUMN "routeEstimatedAt" TIMESTAMP(3);
