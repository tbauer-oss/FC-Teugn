CREATE TYPE "DataSubjectRequestType" AS ENUM ('ERASURE', 'RECTIFICATION');
CREATE TYPE "DataSubjectRequestStatus" AS ENUM ('RECEIVED', 'IN_REVIEW', 'COMPLETED', 'REJECTED');

CREATE TABLE "DataSubjectRequest" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "type" "DataSubjectRequestType" NOT NULL,
  "status" "DataSubjectRequestStatus" NOT NULL DEFAULT 'RECEIVED',
  "reason" TEXT,
  "reviewNote" TEXT,
  "reviewedById" TEXT,
  "reviewedAt" TIMESTAMP(3),
  "completedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "DataSubjectRequest_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "DataSubjectRequest_userId_status_createdAt_idx"
ON "DataSubjectRequest"("userId", "status", "createdAt");
CREATE INDEX "DataSubjectRequest_status_createdAt_idx"
ON "DataSubjectRequest"("status", "createdAt");

ALTER TABLE "DataSubjectRequest"
ADD CONSTRAINT "DataSubjectRequest_userId_fkey"
FOREIGN KEY ("userId") REFERENCES "User"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "DataSubjectRequest"
ADD CONSTRAINT "DataSubjectRequest_reviewedById_fkey"
FOREIGN KEY ("reviewedById") REFERENCES "User"("id")
ON DELETE SET NULL ON UPDATE CASCADE;
