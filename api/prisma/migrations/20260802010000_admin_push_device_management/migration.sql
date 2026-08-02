-- Administrative device blocks must survive automatic token registration.
ALTER TABLE "PushSubscription"
ADD COLUMN "administrativelyDisabledAt" TIMESTAMP(3),
ADD COLUMN "administrativelyDisabledByUserId" TEXT;

CREATE INDEX "PushSubscription_isActive_lastUsedAt_idx"
ON "PushSubscription"("isActive", "lastUsedAt");
