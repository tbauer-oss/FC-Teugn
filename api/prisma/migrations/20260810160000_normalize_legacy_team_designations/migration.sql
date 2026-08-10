-- Alte Spielfeldgrößen-Bezeichnungen wie "E7" oder "E7 1" werden
-- dauerhaft in echte Mannschaftsbezeichnungen (E1, E2, ...) überführt.
WITH normalized AS (
  SELECT
    o."id",
    CASE
      WHEN upper(trim(o."teamDesignation")) ~ '^E7[[:space:]]+[0-9]{1,2}$'
        THEN 'E' || regexp_replace(
          upper(trim(o."teamDesignation")),
          '^E7[[:space:]]+([0-9]{1,2})$',
          E'\\1'
        )
      WHEN upper(trim(o."teamDesignation")) = 'E7' THEN 'E1'
      ELSE upper(trim(o."teamDesignation"))
    END AS designation
  FROM "Opponent" o
  WHERE upper(trim(o."teamDesignation")) = 'E7'
     OR upper(trim(o."teamDesignation")) ~ '^E7[[:space:]]+[0-9]{1,2}$'
)
UPDATE "Opponent" o
SET
  "teamDesignation" = n.designation,
  "normalizedKey" = lower(trim(regexp_replace(
    o."opponentClubId" || ' ' || n.designation,
    '[^a-zA-Z0-9]+',
    ' ',
    'g'
  )))
FROM normalized n
WHERE o."id" = n."id";

-- Auch bereits gespeicherte Spiel- und Tabellenbezeichnungen erhalten keine
-- alten E7-Kürzel mehr. Die zweistufige Ersetzung bewahrt die Teamnummer.
UPDATE "MatchDetails"
SET
  "opponent" = regexp_replace(
    regexp_replace("opponent", 'E7[[:space:]]+([0-9]{1,2})', E'E\\1', 'gi'),
    'E7',
    'E1',
    'gi'
  ),
  "opponentShortName" = CASE
    WHEN "opponentShortName" IS NULL THEN NULL
    ELSE regexp_replace(
      regexp_replace("opponentShortName", 'E7[[:space:]]+([0-9]{1,2})', E'E\\1', 'gi'),
      'E7',
      'E1',
      'gi'
    )
  END
WHERE "opponent" ~* 'E7'
   OR "opponentShortName" ~* 'E7';

UPDATE "LeagueEntry"
SET "displayName" = regexp_replace(
  regexp_replace("displayName", 'E7[[:space:]]+([0-9]{1,2})', E'E\\1', 'gi'),
  'E7',
  'E1',
  'gi'
)
WHERE "displayName" ~* 'E7';

UPDATE "Event"
SET "title" = regexp_replace(
  regexp_replace("title", 'E7[[:space:]]+([0-9]{1,2})', E'E\\1', 'gi'),
  'E7',
  'E1',
  'gi'
)
WHERE "title" ~* 'E7';
