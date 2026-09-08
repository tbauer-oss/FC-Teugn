BEGIN;

ALTER TABLE "CarpoolPassenger" ALTER COLUMN "playerId" DROP NOT NULL;
ALTER TABLE "CarpoolPassenger" ADD COLUMN "passengerUserId" TEXT;
ALTER TABLE "CarpoolNeed" ALTER COLUMN "playerId" DROP NOT NULL;
ALTER TABLE "CarpoolNeed" ADD COLUMN "passengerUserId" TEXT;
ALTER TABLE "CarpoolNeed" ADD COLUMN "groupId" TEXT;

ALTER TABLE "CarpoolPassenger" ADD CONSTRAINT "CarpoolPassenger_passengerUserId_fkey"
  FOREIGN KEY ("passengerUserId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "CarpoolNeed" ADD CONSTRAINT "CarpoolNeed_passengerUserId_fkey"
  FOREIGN KEY ("passengerUserId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "CarpoolPassenger" ADD CONSTRAINT "CarpoolPassenger_one_person"
  CHECK (("playerId" IS NOT NULL) <> ("passengerUserId" IS NOT NULL));
ALTER TABLE "CarpoolNeed" ADD CONSTRAINT "CarpoolNeed_one_person"
  CHECK (("playerId" IS NOT NULL) <> ("passengerUserId" IS NOT NULL));
CREATE UNIQUE INDEX "CarpoolPassenger_offerId_passengerUserId_key" ON "CarpoolPassenger"("offerId", "passengerUserId");
CREATE UNIQUE INDEX "CarpoolNeed_eventId_passengerUserId_key" ON "CarpoolNeed"("eventId", "passengerUserId");

-- Adopt existing open child requests for upcoming, family-visible events.
-- Lock the old tables too: older app versions may still be writing during rollout.
LOCK TABLE "CarpoolOffer", "CarpoolPassenger", "CarpoolNeed" IN SHARE ROW EXCLUSIVE MODE;
DO $$
DECLARE need_record RECORD;
DECLARE selected_offer TEXT;
BEGIN
  FOR need_record IN
    SELECT n.* FROM "CarpoolNeed" n
    JOIN "Event" e ON e.id = n."eventId"
    JOIN "Player" p ON p.id = n."playerId"
    JOIN "User" u ON u.id = n."requestedById"
    WHERE n.status = 'OPEN' AND e.status = 'SCHEDULED'
      AND e."startAt" > CURRENT_TIMESTAMP AND e.visibility <> 'STAFF_ONLY'
      AND (e.type <> 'MATCH' OR e."familyReleasedAt" IS NOT NULL)
      AND p.status = 'ACTIVE' AND u.status = 'APPROVED'
      AND (p."teamId" = e."teamId" OR EXISTS (
        SELECT 1 FROM "EventTargetTeam" t WHERE t."eventId" = e.id AND t."teamId" = p."teamId"))
    ORDER BY n."createdAt", n.id
  LOOP
    IF EXISTS (SELECT 1 FROM "CarpoolPassenger" p JOIN "CarpoolOffer" o ON o.id = p."offerId"
        WHERE o."eventId" = need_record."eventId" AND p."playerId" = need_record."playerId" AND p.status = 'CONFIRMED') THEN
      UPDATE "CarpoolNeed" SET status = 'MATCHED', "updatedAt" = CURRENT_TIMESTAMP WHERE id = need_record.id;
      CONTINUE;
    END IF;
    SELECT o.id INTO selected_offer FROM "CarpoolOffer" o
      WHERE o."eventId" = need_record."eventId" AND o."driverId" <> need_record."requestedById"
        AND o."seatsTotal" > (SELECT COUNT(*) FROM "CarpoolPassenger" p WHERE p."offerId" = o.id AND p.status = 'CONFIRMED')
        AND NOT EXISTS (SELECT 1 FROM "CarpoolPassenger" p WHERE p."offerId" = o.id
          AND p."playerId" = need_record."playerId" AND p.status IN ('DECLINED', 'CANCELLED'))
      ORDER BY o."departureAt", o."createdAt", o.id LIMIT 1;
    IF selected_offer IS NOT NULL THEN
      INSERT INTO "CarpoolPassenger" (id, "offerId", "playerId", "requestedById", status, "createdAt", "updatedAt")
      VALUES ('ride-upgrade-' || need_record.id, selected_offer, need_record."playerId", need_record."requestedById", 'CONFIRMED', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      ON CONFLICT ("offerId", "playerId") DO UPDATE SET status = 'CONFIRMED', "updatedAt" = CURRENT_TIMESTAMP;
      UPDATE "CarpoolPassenger" p SET status = 'CANCELLED', "updatedAt" = CURRENT_TIMESTAMP
        FROM "CarpoolOffer" o WHERE o.id = p."offerId" AND o."eventId" = need_record."eventId"
          AND p."playerId" = need_record."playerId" AND p.status = 'REQUESTED';
      UPDATE "CarpoolNeed" SET status = 'MATCHED', "updatedAt" = CURRENT_TIMESTAMP WHERE id = need_record.id;
    END IF;
  END LOOP;
END $$;

COMMIT;
