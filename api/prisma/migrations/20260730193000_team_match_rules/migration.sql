ALTER TABLE "Team"
ADD COLUMN "periodCount" INTEGER NOT NULL DEFAULT 2,
ADD COLUMN "periodMinutes" INTEGER NOT NULL DEFAULT 30;

UPDATE "Team" AS team
SET
  "periodCount" = CASE
    WHEN age_group."code" = 'A' THEN 2
    WHEN age_group."code" = 'B' THEN 2
    WHEN age_group."code" = 'C' THEN 2
    WHEN age_group."code" = 'D' AND team."gameFormat" = 'FOOTBALL_7' THEN 6
    WHEN age_group."code" = 'D' THEN 2
    WHEN team."gameFormat" = 'FOOTBALL_7' THEN 4
    WHEN team."gameFormat" IN ('FOOTBALL_3', 'FOOTBALL_4', 'FOOTBALL_5') THEN 5
    ELSE 2
  END,
  "periodMinutes" = CASE
    WHEN age_group."code" = 'A' THEN 45
    WHEN age_group."code" = 'B' THEN 40
    WHEN age_group."code" = 'C' THEN 35
    WHEN age_group."code" = 'D' AND team."gameFormat" = 'FOOTBALL_7' THEN 12
    WHEN age_group."code" = 'D' THEN 30
    WHEN team."gameFormat" = 'FOOTBALL_7' THEN 15
    WHEN team."gameFormat" = 'FOOTBALL_5' THEN 12
    WHEN team."gameFormat" = 'FOOTBALL_4' THEN 10
    WHEN team."gameFormat" = 'FOOTBALL_3' THEN 7
    ELSE 30
  END
FROM "AgeGroup" AS age_group
WHERE team."ageGroupId" = age_group."id";
