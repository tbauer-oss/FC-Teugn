CREATE TYPE "TeamTaskStatus" AS ENUM ('OPEN', 'IN_PROGRESS', 'DONE', 'CANCELLED');
CREATE TYPE "EquipmentItemStatus" AS ENUM ('ACTIVE', 'MAINTENANCE', 'LOST', 'RETIRED');
CREATE TYPE "ChecklistRunStatus" AS ENUM ('ACTIVE', 'COMPLETED', 'ARCHIVED');

CREATE TABLE "TeamTask" (
    "id" TEXT NOT NULL,
    "teamId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT,
    "category" TEXT NOT NULL,
    "status" "TeamTaskStatus" NOT NULL DEFAULT 'OPEN',
    "assigneeUserId" TEXT,
    "dueAt" TIMESTAMP(3),
    "reminderAt" TIMESTAMP(3),
    "completedAt" TIMESTAMP(3),
    "createdById" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "TeamTask_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "EquipmentItem" (
    "id" TEXT NOT NULL,
    "teamId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "quantity" INTEGER NOT NULL DEFAULT 1,
    "status" "EquipmentItemStatus" NOT NULL DEFAULT 'ACTIVE',
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "EquipmentItem_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "EquipmentAssignment" (
    "id" TEXT NOT NULL,
    "equipmentItemId" TEXT NOT NULL,
    "assignedToUserId" TEXT,
    "assignedToPlayerId" TEXT,
    "assignedById" TEXT NOT NULL,
    "quantity" INTEGER NOT NULL DEFAULT 1,
    "assignedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "dueAt" TIMESTAMP(3),
    "returnedAt" TIMESTAMP(3),
    "conditionOut" TEXT,
    "conditionIn" TEXT,
    "notes" TEXT,
    CONSTRAINT "EquipmentAssignment_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ChecklistTemplate" (
    "id" TEXT NOT NULL,
    "teamId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "description" TEXT,
    "isArchived" BOOLEAN NOT NULL DEFAULT false,
    "createdById" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "ChecklistTemplate_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ChecklistTemplateItem" (
    "id" TEXT NOT NULL,
    "templateId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "position" INTEGER NOT NULL,
    "isRequired" BOOLEAN NOT NULL DEFAULT true,
    CONSTRAINT "ChecklistTemplateItem_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ChecklistRun" (
    "id" TEXT NOT NULL,
    "teamId" TEXT NOT NULL,
    "templateId" TEXT,
    "title" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "dueAt" TIMESTAMP(3),
    "status" "ChecklistRunStatus" NOT NULL DEFAULT 'ACTIVE',
    "completedAt" TIMESTAMP(3),
    "createdById" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "ChecklistRun_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ChecklistRunItem" (
    "id" TEXT NOT NULL,
    "checklistRunId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "position" INTEGER NOT NULL,
    "isRequired" BOOLEAN NOT NULL DEFAULT true,
    "isCompleted" BOOLEAN NOT NULL DEFAULT false,
    "completedAt" TIMESTAMP(3),
    "completedById" TEXT,
    CONSTRAINT "ChecklistRunItem_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "TeamTask_teamId_status_dueAt_idx" ON "TeamTask"("teamId", "status", "dueAt");
CREATE INDEX "TeamTask_assigneeUserId_status_idx" ON "TeamTask"("assigneeUserId", "status");
CREATE INDEX "EquipmentItem_teamId_status_category_idx" ON "EquipmentItem"("teamId", "status", "category");
CREATE UNIQUE INDEX "EquipmentItem_teamId_name_key" ON "EquipmentItem"("teamId", "name");
CREATE INDEX "EquipmentAssignment_equipmentItemId_returnedAt_idx" ON "EquipmentAssignment"("equipmentItemId", "returnedAt");
CREATE INDEX "EquipmentAssignment_assignedToUserId_returnedAt_idx" ON "EquipmentAssignment"("assignedToUserId", "returnedAt");
CREATE INDEX "EquipmentAssignment_assignedToPlayerId_returnedAt_idx" ON "EquipmentAssignment"("assignedToPlayerId", "returnedAt");
CREATE INDEX "ChecklistTemplate_teamId_isArchived_category_idx" ON "ChecklistTemplate"("teamId", "isArchived", "category");
CREATE UNIQUE INDEX "ChecklistTemplateItem_templateId_position_key" ON "ChecklistTemplateItem"("templateId", "position");
CREATE INDEX "ChecklistRun_teamId_status_dueAt_idx" ON "ChecklistRun"("teamId", "status", "dueAt");
CREATE UNIQUE INDEX "ChecklistRunItem_checklistRunId_position_key" ON "ChecklistRunItem"("checklistRunId", "position");

ALTER TABLE "TeamTask" ADD CONSTRAINT "TeamTask_teamId_fkey" FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "TeamTask" ADD CONSTRAINT "TeamTask_assigneeUserId_fkey" FOREIGN KEY ("assigneeUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "TeamTask" ADD CONSTRAINT "TeamTask_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "EquipmentItem" ADD CONSTRAINT "EquipmentItem_teamId_fkey" FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "EquipmentAssignment" ADD CONSTRAINT "EquipmentAssignment_equipmentItemId_fkey" FOREIGN KEY ("equipmentItemId") REFERENCES "EquipmentItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "EquipmentAssignment" ADD CONSTRAINT "EquipmentAssignment_assignedToUserId_fkey" FOREIGN KEY ("assignedToUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "EquipmentAssignment" ADD CONSTRAINT "EquipmentAssignment_assignedToPlayerId_fkey" FOREIGN KEY ("assignedToPlayerId") REFERENCES "Player"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "EquipmentAssignment" ADD CONSTRAINT "EquipmentAssignment_assignedById_fkey" FOREIGN KEY ("assignedById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "ChecklistTemplate" ADD CONSTRAINT "ChecklistTemplate_teamId_fkey" FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "ChecklistTemplate" ADD CONSTRAINT "ChecklistTemplate_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "ChecklistTemplateItem" ADD CONSTRAINT "ChecklistTemplateItem_templateId_fkey" FOREIGN KEY ("templateId") REFERENCES "ChecklistTemplate"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ChecklistRun" ADD CONSTRAINT "ChecklistRun_teamId_fkey" FOREIGN KEY ("teamId") REFERENCES "Team"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "ChecklistRun" ADD CONSTRAINT "ChecklistRun_templateId_fkey" FOREIGN KEY ("templateId") REFERENCES "ChecklistTemplate"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "ChecklistRun" ADD CONSTRAINT "ChecklistRun_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "ChecklistRunItem" ADD CONSTRAINT "ChecklistRunItem_checklistRunId_fkey" FOREIGN KEY ("checklistRunId") REFERENCES "ChecklistRun"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ChecklistRunItem" ADD CONSTRAINT "ChecklistRunItem_completedById_fkey" FOREIGN KEY ("completedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
