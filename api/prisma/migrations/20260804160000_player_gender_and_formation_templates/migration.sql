CREATE TYPE "PlayerGender" AS ENUM ('MALE', 'FEMALE', 'DIVERSE');

ALTER TABLE "Player"
ADD COLUMN "gender" "PlayerGender";

ALTER TABLE "Team"
ADD COLUMN "formationTemplates" JSONB NOT NULL DEFAULT '[]'::JSONB;
