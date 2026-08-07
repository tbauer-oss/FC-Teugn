-- Sichere, kurzlebige Einmal-Links für den Passwort-Reset per Push.
CREATE TABLE "PasswordResetToken" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "consumedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PasswordResetToken_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "PasswordResetToken_tokenHash_key"
ON "PasswordResetToken"("tokenHash");

CREATE INDEX "PasswordResetToken_userId_consumedAt_expiresAt_idx"
ON "PasswordResetToken"("userId", "consumedAt", "expiresAt");

ALTER TABLE "PasswordResetToken"
ADD CONSTRAINT "PasswordResetToken_userId_fkey"
FOREIGN KEY ("userId") REFERENCES "User"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

-- Bereits geplante, zukünftige Spiele erhalten den neuen sicheren Standard.
-- Später kann die Erinnerung pro Spiel ausdrücklich wieder deaktiviert werden.
UPDATE "Event"
SET
  "reminderMinutes" = ARRAY[1440]::INTEGER[],
  "reminderPushEnabled" = TRUE,
  "reminderSyncPendingAt" = CURRENT_TIMESTAMP
WHERE
  "type" = 'MATCH'
  AND "status" = 'SCHEDULED'
  AND "startAt" > CURRENT_TIMESTAMP
  AND cardinality("reminderMinutes") = 0;
