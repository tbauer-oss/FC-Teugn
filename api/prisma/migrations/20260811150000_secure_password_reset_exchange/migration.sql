ALTER TABLE "PasswordResetToken"
ADD COLUMN "exchangedAt" TIMESTAMP(3),
ADD COLUMN "claimedBySubscriptionId" TEXT;

CREATE INDEX "PasswordResetToken_claimedBySubscriptionId_exchangedAt_idx"
ON "PasswordResetToken"("claimedBySubscriptionId", "exchangedAt");
