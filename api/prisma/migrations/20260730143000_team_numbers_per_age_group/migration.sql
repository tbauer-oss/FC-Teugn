ALTER TABLE "Team"
ADD COLUMN "teamNumber" INTEGER;

WITH ranked_teams AS (
  SELECT
    "id",
    ROW_NUMBER() OVER (
      PARTITION BY "ageGroupId"
      ORDER BY
        CASE
          WHEN COALESCE("shortName", "name") ~ '[0-9]+'
            THEN ((regexp_match(COALESCE("shortName", "name"), '([0-9]+)'))[1])::INTEGER
          ELSE 2147483647
        END,
        "createdAt",
        "id"
    )::INTEGER AS "assignedNumber"
  FROM "Team"
)
UPDATE "Team"
SET "teamNumber" = ranked_teams."assignedNumber"
FROM ranked_teams
WHERE "Team"."id" = ranked_teams."id";

UPDATE "Team"
SET
  "name" = UPPER("AgeGroup"."code") || "Team"."teamNumber",
  "shortName" = UPPER("AgeGroup"."code") || "Team"."teamNumber"
FROM "AgeGroup"
WHERE "Team"."ageGroupId" = "AgeGroup"."id";

ALTER TABLE "Team"
ALTER COLUMN "teamNumber" SET NOT NULL,
ALTER COLUMN "teamNumber" SET DEFAULT 1;

CREATE UNIQUE INDEX "Team_ageGroupId_teamNumber_key"
ON "Team"("ageGroupId", "teamNumber");
