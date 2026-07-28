import {
  ChecklistRunStatus,
  EquipmentItemStatus,
  Prisma,
  TeamTaskStatus,
} from '@prisma/client';
import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { hasPermission, Permission } from '../security/permissions';
import { accessibleTeamIds } from '../services/team-access';

function clean(value: unknown, maximum = 1000) {
  if (typeof value !== 'string') return null;
  const normalized = value.trim();
  return normalized ? normalized.slice(0, maximum) : null;
}

function positiveInteger(value: unknown, fallback = 1, maximum = 999) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 && parsed <= maximum
    ? parsed
    : fallback;
}

function dateValue(value: unknown) {
  if (!value) return null;
  const parsed = new Date(String(value));
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function enumValue<T extends Record<string, string>>(
  values: T,
  value: unknown,
  fallback: T[keyof T],
) {
  const normalized = String(value ?? '').toUpperCase();
  return (Object.values(values) as string[]).includes(normalized)
    ? (normalized as T[keyof T])
    : fallback;
}

async function scopedTeamId(req: Request) {
  const teamIds = await accessibleTeamIds(req.user!);
  const requested = clean(req.body?.teamId ?? req.query.teamId, 100);
  if (requested && teamIds.includes(requested)) return requested;
  if (requested) return null;
  return teamIds.includes(req.user!.teamId) ? req.user!.teamId : teamIds[0] ?? null;
}

async function isTeamMember(userId: string, teamId: string) {
  return Boolean(
    await prisma.user.findFirst({
      where: {
        id: userId,
        status: 'APPROVED',
        OR: [
          { teamId },
          { memberships: { some: { teamId, status: 'APPROVED' } } },
        ],
      },
      select: { id: true },
    }),
  );
}

const assignmentInclude = {
  assignedToUser: { select: { id: true, name: true, role: true } },
  assignedToPlayer: {
    select: { id: true, firstName: true, lastName: true, preferredName: true },
  },
  assignedBy: { select: { id: true, name: true } },
} as const;

export async function teamOperationsOverview(req: Request, res: Response) {
  const user = req.user!;
  const teamId = await scopedTeamId(req);
  if (!teamId) return res.status(403).json({ message: 'Mannschaft nicht erlaubt.' });
  const canManage = hasPermission(user.role, Permission.MANAGE_TEAM_OPERATIONS);
  const taskWhere: Prisma.TeamTaskWhereInput = {
    teamId,
    ...(canManage
      ? {}
      : {
          OR: [{ assigneeUserId: user.id }, { createdById: user.id }],
        }),
  };

  const [tasks, equipment, templates, checklistRuns, members, players] =
    await Promise.all([
      prisma.teamTask.findMany({
        where: taskWhere,
        include: {
          assignee: { select: { id: true, name: true, role: true } },
          createdBy: { select: { id: true, name: true } },
        },
        orderBy: [{ status: 'asc' }, { dueAt: 'asc' }, { createdAt: 'desc' }],
        take: 200,
      }),
      prisma.equipmentItem.findMany({
        where: { teamId },
        include: {
          assignments: {
            where: { returnedAt: null },
            include: assignmentInclude,
            orderBy: { assignedAt: 'desc' },
          },
        },
        orderBy: [{ status: 'asc' }, { category: 'asc' }, { name: 'asc' }],
        take: 200,
      }),
      prisma.checklistTemplate.findMany({
        where: { teamId, isArchived: false },
        include: { items: { orderBy: { position: 'asc' } } },
        orderBy: [{ category: 'asc' }, { title: 'asc' }],
        take: 100,
      }),
      prisma.checklistRun.findMany({
        where: { teamId, status: { not: ChecklistRunStatus.ARCHIVED } },
        include: {
          items: {
            orderBy: { position: 'asc' },
            include: { completedBy: { select: { id: true, name: true } } },
          },
        },
        orderBy: [{ status: 'asc' }, { dueAt: 'asc' }, { createdAt: 'desc' }],
        take: 100,
      }),
      prisma.user.findMany({
        where: {
          status: 'APPROVED',
          OR: [
            { teamId },
            { memberships: { some: { teamId, status: 'APPROVED' } } },
          ],
        },
        select: { id: true, name: true, role: true },
        orderBy: { name: 'asc' },
      }),
      prisma.player.findMany({
        where: { teamId, status: { not: 'LEFT' } },
        select: {
          id: true,
          firstName: true,
          lastName: true,
          preferredName: true,
        },
        orderBy: [{ lastName: 'asc' }, { firstName: 'asc' }],
      }),
    ]);

  return res.json({
    teamId,
    canManage,
    tasks,
    equipment,
    checklistTemplates: templates,
    checklistRuns,
    members,
    players,
  });
}

export async function createTeamTask(req: Request, res: Response) {
  const user = req.user!;
  const teamId = await scopedTeamId(req);
  const title = clean(req.body?.title, 160);
  const category = clean(req.body?.category, 60) ?? 'SONSTIGES';
  const assigneeUserId = clean(req.body?.assigneeUserId, 100);
  if (!teamId) return res.status(403).json({ message: 'Mannschaft nicht erlaubt.' });
  if (!title) return res.status(400).json({ message: 'Aufgabentitel fehlt.' });
  if (assigneeUserId && !(await isTeamMember(assigneeUserId, teamId))) {
    return res.status(400).json({ message: 'Verantwortliche Person gehört nicht zur Mannschaft.' });
  }
  const task = await prisma.$transaction(async (tx) => {
    const created = await tx.teamTask.create({
      data: {
        teamId,
        title,
        category,
        description: clean(req.body?.description, 2000),
        assigneeUserId,
        dueAt: dateValue(req.body?.dueAt),
        reminderAt: dateValue(req.body?.reminderAt),
        createdById: user.id,
      },
      include: {
        assignee: { select: { id: true, name: true, role: true } },
        createdBy: { select: { id: true, name: true } },
      },
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId,
        action: 'TEAM_TASK_CREATED',
        entityType: 'TeamTask',
        entityId: created.id,
        metadata: { title, category, assigneeUserId, dueAt: created.dueAt },
      },
    });
    return created;
  });
  return res.status(201).json(task);
}

export async function updateTeamTask(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const existing = await prisma.teamTask.findFirst({
    where: { id: req.params.id, teamId: { in: teamIds } },
  });
  if (!existing) return res.status(404).json({ message: 'Aufgabe nicht gefunden.' });
  const assigneeUserId =
    req.body?.assigneeUserId === null ? null : clean(req.body?.assigneeUserId, 100);
  if (assigneeUserId && !(await isTeamMember(assigneeUserId, existing.teamId))) {
    return res.status(400).json({ message: 'Verantwortliche Person gehört nicht zur Mannschaft.' });
  }
  const status = enumValue(TeamTaskStatus, req.body?.status, existing.status);
  const task = await prisma.$transaction(async (tx) => {
    const updated = await tx.teamTask.update({
      where: { id: existing.id },
      data: {
        title: clean(req.body?.title, 160) ?? existing.title,
        description:
          req.body?.description === null
            ? null
            : clean(req.body?.description, 2000) ?? existing.description,
        category: clean(req.body?.category, 60) ?? existing.category,
        status,
        assigneeUserId:
          req.body?.assigneeUserId === undefined
            ? existing.assigneeUserId
            : assigneeUserId,
        dueAt:
          req.body?.dueAt === undefined ? existing.dueAt : dateValue(req.body.dueAt),
        reminderAt:
          req.body?.reminderAt === undefined
            ? existing.reminderAt
            : dateValue(req.body.reminderAt),
        completedAt:
          status === TeamTaskStatus.DONE
            ? existing.completedAt ?? new Date()
            : null,
      },
      include: {
        assignee: { select: { id: true, name: true, role: true } },
        createdBy: { select: { id: true, name: true } },
      },
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: existing.teamId,
        action: 'TEAM_TASK_UPDATED',
        entityType: 'TeamTask',
        entityId: existing.id,
        metadata: { before: existing, after: updated },
      },
    });
    return updated;
  });
  return res.json(task);
}

export async function createEquipmentItem(req: Request, res: Response) {
  const user = req.user!;
  const teamId = await scopedTeamId(req);
  const name = clean(req.body?.name, 160);
  if (!teamId) return res.status(403).json({ message: 'Mannschaft nicht erlaubt.' });
  if (!name) return res.status(400).json({ message: 'Materialname fehlt.' });
  const duplicate = await prisma.equipmentItem.findUnique({
    where: { teamId_name: { teamId, name } },
  });
  if (duplicate) {
    return res.status(409).json({ message: 'Dieses Material ist bereits vorhanden.' });
  }
  const item = await prisma.$transaction(async (tx) => {
    const created = await tx.equipmentItem.create({
      data: {
        teamId,
        name,
        category: clean(req.body?.category, 60) ?? 'SONSTIGES',
        quantity: positiveInteger(req.body?.quantity),
        notes: clean(req.body?.notes, 1000),
      },
      include: { assignments: true },
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId,
        action: 'EQUIPMENT_CREATED',
        entityType: 'EquipmentItem',
        entityId: created.id,
        metadata: { name, quantity: created.quantity, category: created.category },
      },
    });
    return created;
  });
  return res.status(201).json(item);
}

export async function updateEquipmentItem(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const existing = await prisma.equipmentItem.findFirst({
    where: { id: req.params.id, teamId: { in: teamIds } },
  });
  if (!existing) return res.status(404).json({ message: 'Material nicht gefunden.' });
  const active = await prisma.equipmentAssignment.aggregate({
    where: { equipmentItemId: existing.id, returnedAt: null },
    _sum: { quantity: true },
  });
  const quantity = positiveInteger(req.body?.quantity, existing.quantity);
  if (quantity < (active._sum.quantity ?? 0)) {
    return res.status(409).json({
      message: 'Bestand kann nicht unter die aktuell ausgegebene Menge reduziert werden.',
    });
  }
  const item = await prisma.$transaction(async (tx) => {
    const updated = await tx.equipmentItem.update({
      where: { id: existing.id },
      data: {
        name: clean(req.body?.name, 160) ?? existing.name,
        category: clean(req.body?.category, 60) ?? existing.category,
        quantity,
        status: enumValue(EquipmentItemStatus, req.body?.status, existing.status),
        notes:
          req.body?.notes === null
            ? null
            : clean(req.body?.notes, 1000) ?? existing.notes,
      },
      include: {
        assignments: { where: { returnedAt: null }, include: assignmentInclude },
      },
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: existing.teamId,
        action: 'EQUIPMENT_UPDATED',
        entityType: 'EquipmentItem',
        entityId: existing.id,
        metadata: { before: existing, after: updated },
      },
    });
    return updated;
  });
  return res.json(item);
}

export async function assignEquipment(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const item = await prisma.equipmentItem.findFirst({
    where: {
      id: req.params.id,
      teamId: { in: teamIds },
      status: EquipmentItemStatus.ACTIVE,
    },
  });
  if (!item) return res.status(404).json({ message: 'Aktives Material nicht gefunden.' });
  const assignedToUserId = clean(req.body?.assignedToUserId, 100);
  const assignedToPlayerId = clean(req.body?.assignedToPlayerId, 100);
  if (Boolean(assignedToUserId) === Boolean(assignedToPlayerId)) {
    return res.status(400).json({ message: 'Genau eine Person muss ausgewählt werden.' });
  }
  if (assignedToUserId && !(await isTeamMember(assignedToUserId, item.teamId))) {
    return res.status(400).json({ message: 'Empfänger gehört nicht zur Mannschaft.' });
  }
  if (assignedToPlayerId) {
    const player = await prisma.player.findFirst({
      where: { id: assignedToPlayerId, teamId: item.teamId, status: { not: 'LEFT' } },
      select: { id: true },
    });
    if (!player) return res.status(400).json({ message: 'Spieler gehört nicht zur Mannschaft.' });
  }
  const quantity = positiveInteger(req.body?.quantity);
  let assignment;
  try {
    assignment = await prisma.$transaction(
      async (tx) => {
        const currentItem = await tx.equipmentItem.findUniqueOrThrow({
          where: { id: item.id },
        });
        const active = await tx.equipmentAssignment.aggregate({
          where: { equipmentItemId: item.id, returnedAt: null },
          _sum: { quantity: true },
        });
        if ((active._sum.quantity ?? 0) + quantity > currentItem.quantity) {
          throw new Error('EQUIPMENT_CAPACITY');
        }
        const created = await tx.equipmentAssignment.create({
          data: {
            equipmentItemId: item.id,
            assignedToUserId,
            assignedToPlayerId,
            assignedById: user.id,
            quantity,
            dueAt: dateValue(req.body?.dueAt),
            conditionOut: clean(req.body?.conditionOut, 300),
            notes: clean(req.body?.notes, 1000),
          },
          include: assignmentInclude,
        });
        await tx.auditLog.create({
          data: {
            actorId: user.id,
            teamId: item.teamId,
            action: 'EQUIPMENT_ASSIGNED',
            entityType: 'EquipmentAssignment',
            entityId: created.id,
            metadata: {
              equipmentItemId: item.id,
              assignedToUserId,
              assignedToPlayerId,
              quantity,
            },
          },
        });
        return created;
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );
  } catch (error) {
    if (
      (error instanceof Error && error.message === 'EQUIPMENT_CAPACITY') ||
      (typeof error === 'object' &&
        error !== null &&
        'code' in error &&
        error.code === 'P2034')
    ) {
      return res.status(409).json({
        message:
          'Der Bestand wurde parallel geändert. Verfügbarkeit bitte neu laden.',
      });
    }
    throw error;
  }
  return res.status(201).json(assignment);
}

export async function returnEquipment(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const existing = await prisma.equipmentAssignment.findFirst({
    where: {
      id: req.params.assignmentId,
      returnedAt: null,
      equipmentItem: { teamId: { in: teamIds } },
    },
    include: { equipmentItem: { select: { teamId: true } } },
  });
  if (!existing) return res.status(404).json({ message: 'Offene Ausgabe nicht gefunden.' });
  const assignment = await prisma.$transaction(async (tx) => {
    const updated = await tx.equipmentAssignment.update({
      where: { id: existing.id },
      data: {
        returnedAt: new Date(),
        conditionIn: clean(req.body?.conditionIn, 300),
        notes: clean(req.body?.notes, 1000) ?? existing.notes,
      },
      include: assignmentInclude,
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: existing.equipmentItem.teamId,
        action: 'EQUIPMENT_RETURNED',
        entityType: 'EquipmentAssignment',
        entityId: existing.id,
        metadata: { equipmentItemId: existing.equipmentItemId, quantity: existing.quantity },
      },
    });
    return updated;
  });
  return res.json(assignment);
}

export function checklistItems(value: unknown) {
  if (!Array.isArray(value)) return [];
  return value
    .slice(0, 80)
    .map((item, position) => {
      const record: Record<string, unknown> =
        typeof item === 'object' && item !== null
          ? (item as Record<string, unknown>)
          : { title: item };
      const title = clean(record.title, 200);
      return title
        ? {
            title,
            position,
            isRequired: record.isRequired !== false,
          }
        : null;
    })
    .filter((item): item is { title: string; position: number; isRequired: boolean } =>
      Boolean(item),
    );
}

export async function createChecklistTemplate(req: Request, res: Response) {
  const user = req.user!;
  const teamId = await scopedTeamId(req);
  const title = clean(req.body?.title, 160);
  const items = checklistItems(req.body?.items);
  if (!teamId) return res.status(403).json({ message: 'Mannschaft nicht erlaubt.' });
  if (!title || items.length === 0) {
    return res.status(400).json({ message: 'Titel und mindestens ein Punkt sind erforderlich.' });
  }
  const template = await prisma.$transaction(async (tx) => {
    const created = await tx.checklistTemplate.create({
      data: {
        teamId,
        title,
        category: clean(req.body?.category, 60) ?? 'SONSTIGES',
        description: clean(req.body?.description, 1000),
        createdById: user.id,
        items: { create: items },
      },
      include: { items: { orderBy: { position: 'asc' } } },
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId,
        action: 'CHECKLIST_TEMPLATE_CREATED',
        entityType: 'ChecklistTemplate',
        entityId: created.id,
        metadata: { title, itemCount: items.length },
      },
    });
    return created;
  });
  return res.status(201).json(template);
}

export async function createChecklistRun(req: Request, res: Response) {
  const user = req.user!;
  const teamId = await scopedTeamId(req);
  const templateId = clean(req.body?.templateId, 100);
  if (!teamId || !templateId) {
    return res.status(400).json({ message: 'Mannschaft und Vorlage sind erforderlich.' });
  }
  const template = await prisma.checklistTemplate.findFirst({
    where: { id: templateId, teamId, isArchived: false },
    include: { items: { orderBy: { position: 'asc' } } },
  });
  if (!template) return res.status(404).json({ message: 'Checklisten-Vorlage nicht gefunden.' });
  const run = await prisma.$transaction(async (tx) => {
    const created = await tx.checklistRun.create({
      data: {
        teamId,
        templateId,
        title: clean(req.body?.title, 160) ?? template.title,
        category: template.category,
        dueAt: dateValue(req.body?.dueAt),
        createdById: user.id,
        items: {
          create: template.items.map((item) => ({
            title: item.title,
            position: item.position,
            isRequired: item.isRequired,
          })),
        },
      },
      include: { items: { orderBy: { position: 'asc' } } },
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId,
        action: 'CHECKLIST_STARTED',
        entityType: 'ChecklistRun',
        entityId: created.id,
        metadata: { templateId, title: created.title, dueAt: created.dueAt },
      },
    });
    return created;
  });
  return res.status(201).json(run);
}

export async function setChecklistItem(req: Request, res: Response) {
  const user = req.user!;
  const teamIds = await accessibleTeamIds(user);
  const item = await prisma.checklistRunItem.findFirst({
    where: {
      id: req.params.itemId,
      checklistRunId: req.params.runId,
      checklistRun: { teamId: { in: teamIds }, status: ChecklistRunStatus.ACTIVE },
    },
    include: { checklistRun: { select: { teamId: true } } },
  });
  if (!item) return res.status(404).json({ message: 'Aktiver Checklistenpunkt nicht gefunden.' });
  const isCompleted = req.body?.isCompleted === true;
  const run = await prisma.$transaction(async (tx) => {
    await tx.checklistRunItem.update({
      where: { id: item.id },
      data: {
        isCompleted,
        completedAt: isCompleted ? new Date() : null,
        completedById: isCompleted ? user.id : null,
      },
    });
    const remainingRequired = await tx.checklistRunItem.count({
      where: {
        checklistRunId: req.params.runId,
        isRequired: true,
        isCompleted: false,
      },
    });
    const updated = await tx.checklistRun.update({
      where: { id: req.params.runId },
      data: {
        status:
          remainingRequired === 0
            ? ChecklistRunStatus.COMPLETED
            : ChecklistRunStatus.ACTIVE,
        completedAt: remainingRequired === 0 ? new Date() : null,
      },
      include: {
        items: {
          orderBy: { position: 'asc' },
          include: { completedBy: { select: { id: true, name: true } } },
        },
      },
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: item.checklistRun.teamId,
        action: isCompleted ? 'CHECKLIST_ITEM_COMPLETED' : 'CHECKLIST_ITEM_REOPENED',
        entityType: 'ChecklistRunItem',
        entityId: item.id,
        metadata: { checklistRunId: req.params.runId },
      },
    });
    return updated;
  });
  return res.json(run);
}
