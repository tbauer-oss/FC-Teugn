CREATE TABLE "IndoorOccupancyEntry" (
    "id" TEXT NOT NULL,
    "seasonId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "location" TEXT NOT NULL,
    "startAt" TIMESTAMP(3) NOT NULL,
    "endAt" TIMESTAMP(3) NOT NULL,
    "notes" TEXT,
    "createdById" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "IndoorOccupancyEntry_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "IndoorOccupancyEntry_seasonId_startAt_idx"
ON "IndoorOccupancyEntry"("seasonId", "startAt");

ALTER TABLE "IndoorOccupancyEntry"
ADD CONSTRAINT "IndoorOccupancyEntry_seasonId_fkey"
FOREIGN KEY ("seasonId") REFERENCES "Season"("id")
ON DELETE CASCADE ON UPDATE CASCADE;
