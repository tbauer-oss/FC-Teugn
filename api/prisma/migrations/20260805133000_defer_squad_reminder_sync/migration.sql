ALTER TABLE "Event"
  ADD COLUMN "reminderSyncPendingAt" TIMESTAMP(3);

CREATE INDEX "Event_reminderSyncPendingAt_idx"
  ON "Event"("reminderSyncPendingAt");
