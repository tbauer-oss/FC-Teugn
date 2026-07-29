-- TRAINER_ADMIN was the original highest application role. Existing approved
-- accounts with that role are the installations' administrators and become
-- explicit, unrestricted SUPER_ADMIN accounts.
UPDATE "User"
SET "role" = 'SUPER_ADMIN'
WHERE "role" = 'TRAINER_ADMIN'
  AND "status" = 'APPROVED';

UPDATE "TeamMembership"
SET "role" = 'SUPER_ADMIN'
WHERE "userId" IN (
  SELECT "id"
  FROM "User"
  WHERE "role" = 'SUPER_ADMIN'
    AND "status" = 'APPROVED'
);
