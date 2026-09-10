-- Existing, individually planned squads stay independent.
ALTER TABLE "Squad" ADD COLUMN "inheritsTournamentSquad" BOOLEAN NOT NULL DEFAULT false;
