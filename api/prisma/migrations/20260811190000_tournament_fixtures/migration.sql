-- A tournament is the shared organizational event. Its individual fixtures
-- are full match events so every pairing owns an independent squad, lineup,
-- live ticker and result while remaining grouped below the tournament.
ALTER TABLE "Event"
ADD COLUMN "parentTournamentId" TEXT;

ALTER TABLE "Event"
ADD CONSTRAINT "Event_parentTournamentId_fkey"
FOREIGN KEY ("parentTournamentId") REFERENCES "Event"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

CREATE INDEX "Event_parentTournamentId_startAt_idx"
ON "Event"("parentTournamentId", "startAt");
