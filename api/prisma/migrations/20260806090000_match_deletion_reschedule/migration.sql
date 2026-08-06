ALTER TABLE "Event"
ADD COLUMN "meetingLocation" TEXT;

-- Bestehende Spiele erhalten dieselben verbindlichen Vereinsstandards wie
-- neu angelegte und später bearbeitete Begegnungen.
UPDATE "Event"
SET "location" = 'Stadion am Kreutweg, Teugn'
WHERE "type" = 'MATCH' AND "homeAway" = 'HOME';

UPDATE "Event"
SET "meetingLocation" = 'Vereinsheim Teugn'
WHERE "type" = 'MATCH'
  AND "homeAway" = 'AWAY'
  AND ("meetingLocation" IS NULL OR BTRIM("meetingLocation") = '');
