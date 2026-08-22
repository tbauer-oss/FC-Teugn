ALTER TABLE "Team"
ADD COLUMN "isPlayingCommunity" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "playingCommunityName" TEXT,
ADD COLUMN "playingCommunityShortName" TEXT,
ADD COLUMN "playingCommunityLogoUrl" TEXT;

-- FC Teugn Talents currently runs its A-youth as a playing community with
-- SV Saal/Donau. Existing A-youth teams receive the correct match identity
-- immediately; it can still be changed later in the team settings.
UPDATE "Team"
SET
  "isPlayingCommunity" = true,
  "playingCommunityName" = '(SG) SV Saal/Donau',
  "playingCommunityShortName" = 'SG Saal/Donau'
FROM "AgeGroup"
WHERE "Team"."ageGroupId" = "AgeGroup"."id"
  AND UPPER("AgeGroup"."code") = 'A'
  AND "Team"."deletedAt" IS NULL;

-- Older A-youth matches may still contain the club identity in their stored
-- title. Update those records as well because notifications and exports can
-- legitimately use the stored title without loading the complete team.
UPDATE "Event"
SET "title" = REPLACE("Event"."title", 'FC Teugn', '(SG) SV Saal/Donau')
FROM "Team", "AgeGroup"
WHERE "Event"."teamId" = "Team"."id"
  AND "Team"."ageGroupId" = "AgeGroup"."id"
  AND UPPER("AgeGroup"."code") = 'A'
  AND "Event"."type" = 'MATCH'
  AND "Event"."title" LIKE '%FC Teugn%';
