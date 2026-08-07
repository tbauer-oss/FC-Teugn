ALTER TABLE "User" ADD COLUMN "accountDeletedAt" TIMESTAMP(3);

CREATE INDEX "User_accountDeletedAt_idx" ON "User"("accountDeletedAt");
