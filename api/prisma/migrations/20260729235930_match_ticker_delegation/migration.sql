CREATE TABLE "MatchTickerDelegate" (
    "id" TEXT NOT NULL,
    "eventId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "grantedById" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),

    CONSTRAINT "MatchTickerDelegate_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "MatchTickerDelegate_eventId_key"
ON "MatchTickerDelegate"("eventId");

CREATE INDEX "MatchTickerDelegate_userId_revokedAt_idx"
ON "MatchTickerDelegate"("userId", "revokedAt");

ALTER TABLE "MatchTickerDelegate"
ADD CONSTRAINT "MatchTickerDelegate_eventId_fkey"
FOREIGN KEY ("eventId") REFERENCES "Event"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "MatchTickerDelegate"
ADD CONSTRAINT "MatchTickerDelegate_userId_fkey"
FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "MatchTickerDelegate"
ADD CONSTRAINT "MatchTickerDelegate_grantedById_fkey"
FOREIGN KEY ("grantedById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
