CREATE TABLE "TrainingPlanCoach" (
  "trainingPlanId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "TrainingPlanCoach_pkey" PRIMARY KEY ("trainingPlanId", "userId")
);

CREATE INDEX "TrainingPlanCoach_userId_idx"
  ON "TrainingPlanCoach"("userId");

ALTER TABLE "TrainingPlanCoach"
  ADD CONSTRAINT "TrainingPlanCoach_trainingPlanId_fkey"
  FOREIGN KEY ("trainingPlanId") REFERENCES "TrainingPlan"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "TrainingPlanCoach"
  ADD CONSTRAINT "TrainingPlanCoach_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
