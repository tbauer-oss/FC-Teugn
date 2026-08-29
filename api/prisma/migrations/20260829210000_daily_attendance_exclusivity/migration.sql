-- Speeds up the transactional lookup that guarantees at most one accepted
-- event per player and local calendar day.
CREATE INDEX "Attendance_playerId_status_idx" ON "Attendance"("playerId", "status");
