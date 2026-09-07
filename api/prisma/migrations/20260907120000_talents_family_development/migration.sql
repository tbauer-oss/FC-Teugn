-- AlterTable
ALTER TABLE "Event" ADD COLUMN     "responseRevisionAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "Attendance" ADD COLUMN     "absenceId" TEXT,
ADD COLUMN     "beforeAbsence" JSONB;

-- AlterTable
ALTER TABLE "ExternalReference" ADD COLUMN     "sourceSnapshot" JSONB;

-- AlterTable
ALTER TABLE "ChecklistRun" ADD COLUMN     "eventId" TEXT;

-- CreateTable
CREATE TABLE "TalentsNotice" (
    "id" TEXT NOT NULL,
    "recipients" TEXT[],
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "actionUrl" TEXT NOT NULL,
    "entityId" TEXT NOT NULL,
    "category" "NotificationCategory" NOT NULL DEFAULT 'ANNOUNCEMENT',
    "deliveredAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "TalentsNotice_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PlayerAbsence" (
    "id" TEXT NOT NULL,
    "playerId" TEXT NOT NULL,
    "createdById" TEXT NOT NULL,
    "startsOn" TEXT NOT NULL,
    "endsOn" TEXT NOT NULL,
    "weekdays" INTEGER[] DEFAULT ARRAY[]::INTEGER[],
    "teamIds" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "eventTypes" TEXT[] DEFAULT ARRAY['TRAINING', 'MATCH']::TEXT[],
    "reason" TEXT,
    "endedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PlayerAbsence_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "EventChange" (
    "id" TEXT NOT NULL,
    "eventId" TEXT NOT NULL,
    "before" JSONB NOT NULL,
    "after" JSONB NOT NULL,
    "fields" TEXT[],
    "deliveredAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "EventChange_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TeamPoll" (
    "id" TEXT NOT NULL,
    "authorId" TEXT NOT NULL,
    "teamIds" TEXT[],
    "question" TEXT NOT NULL,
    "options" TEXT[],
    "multiple" BOOLEAN NOT NULL DEFAULT false,
    "unitType" TEXT NOT NULL,
    "resultsVisibility" TEXT NOT NULL DEFAULT 'AFTER_CLOSE',
    "endsAt" TIMESTAMP(3) NOT NULL,
    "closedAt" TIMESTAMP(3),
    "archivedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "TeamPoll_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PollUnit" (
    "id" TEXT NOT NULL,
    "pollId" TEXT NOT NULL,
    "unitKey" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "authorizedUserIds" TEXT[],
    "playerIds" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "choices" INTEGER[] DEFAULT ARRAY[]::INTEGER[],
    "respondedById" TEXT,
    "respondedAt" TIMESTAMP(3),

    CONSTRAINT "PollUnit_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LearningGoal" (
    "id" TEXT NOT NULL,
    "playerId" TEXT NOT NULL,
    "teamId" TEXT NOT NULL,
    "authorId" TEXT NOT NULL,
    "responsibleUserId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "startsOn" TEXT NOT NULL,
    "endsOn" TEXT NOT NULL,
    "visibility" TEXT NOT NULL DEFAULT 'STAFF_ONLY',
    "status" TEXT NOT NULL DEFAULT 'ACTIVE',
    "exerciseIds" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "trainingPlanIds" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "LearningGoal_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "GoalObservation" (
    "id" TEXT NOT NULL,
    "goalId" TEXT NOT NULL,
    "authorId" TEXT NOT NULL,
    "note" TEXT NOT NULL,
    "progress" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "GoalObservation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TeamInvitation" (
    "id" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "teamId" TEXT NOT NULL,
    "createdById" TEXT NOT NULL,
    "role" "Role" NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "TeamInvitation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "InvitationClaim" (
    "invitationId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "InvitationClaim_pkey" PRIMARY KEY ("invitationId","userId")
);

-- CreateIndex
CREATE INDEX "TalentsNotice_deliveredAt_createdAt_idx" ON "TalentsNotice"("deliveredAt", "createdAt");

-- CreateIndex
CREATE INDEX "PlayerAbsence_playerId_startsOn_endsOn_idx" ON "PlayerAbsence"("playerId", "startsOn", "endsOn");

-- CreateIndex
CREATE INDEX "EventChange_deliveredAt_createdAt_idx" ON "EventChange"("deliveredAt", "createdAt");

-- CreateIndex
CREATE INDEX "TeamPoll_endsAt_archivedAt_idx" ON "TeamPoll"("endsAt", "archivedAt");

-- CreateIndex
CREATE UNIQUE INDEX "PollUnit_pollId_unitKey_key" ON "PollUnit"("pollId", "unitKey");

-- CreateIndex
CREATE INDEX "LearningGoal_playerId_status_idx" ON "LearningGoal"("playerId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "TeamInvitation_tokenHash_key" ON "TeamInvitation"("tokenHash");

-- CreateIndex
CREATE UNIQUE INDEX "ChecklistRun_eventId_key" ON "ChecklistRun"("eventId");

-- AddForeignKey
ALTER TABLE "ChecklistRun" ADD CONSTRAINT "ChecklistRun_eventId_fkey" FOREIGN KEY ("eventId") REFERENCES "Event"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PlayerAbsence" ADD CONSTRAINT "PlayerAbsence_playerId_fkey" FOREIGN KEY ("playerId") REFERENCES "Player"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "EventChange" ADD CONSTRAINT "EventChange_eventId_fkey" FOREIGN KEY ("eventId") REFERENCES "Event"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PollUnit" ADD CONSTRAINT "PollUnit_pollId_fkey" FOREIGN KEY ("pollId") REFERENCES "TeamPoll"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LearningGoal" ADD CONSTRAINT "LearningGoal_playerId_fkey" FOREIGN KEY ("playerId") REFERENCES "Player"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GoalObservation" ADD CONSTRAINT "GoalObservation_goalId_fkey" FOREIGN KEY ("goalId") REFERENCES "LearningGoal"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TeamInvitation" ADD CONSTRAINT "TeamInvitation_teamId_fkey" FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InvitationClaim" ADD CONSTRAINT "InvitationClaim_invitationId_fkey" FOREIGN KEY ("invitationId") REFERENCES "TeamInvitation"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InvitationClaim" ADD CONSTRAINT "InvitationClaim_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
