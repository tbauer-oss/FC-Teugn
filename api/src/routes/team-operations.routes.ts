import { Router } from 'express';
import {
  assignEquipment,
  createChecklistRun,
  createChecklistTemplate,
  createEquipmentItem,
  createTeamTask,
  returnEquipment,
  setChecklistItem,
  teamOperationsOverview,
  updateEquipmentItem,
  updateTeamTask,
} from '../controllers/team-operations.controller';
import { requireApproved, requireAuth, requirePermission } from '../middleware/auth';
import { idempotencyMiddleware } from '../middleware/idempotency';
import { Permission } from '../security/permissions';

const router = Router();
router.use(requireAuth);
router.use(requireApproved);
router.use(idempotencyMiddleware);

router.get(
  '/',
  requirePermission(Permission.VIEW_TEAM_OPERATIONS),
  teamOperationsOverview,
);
router.post(
  '/tasks',
  requirePermission(Permission.MANAGE_TEAM_OPERATIONS),
  createTeamTask,
);
router.put(
  '/tasks/:id',
  requirePermission(Permission.MANAGE_TEAM_OPERATIONS),
  updateTeamTask,
);
router.post(
  '/equipment',
  requirePermission(Permission.MANAGE_TEAM_OPERATIONS),
  createEquipmentItem,
);
router.put(
  '/equipment/:id',
  requirePermission(Permission.MANAGE_TEAM_OPERATIONS),
  updateEquipmentItem,
);
router.post(
  '/equipment/:id/assignments',
  requirePermission(Permission.MANAGE_TEAM_OPERATIONS),
  assignEquipment,
);
router.post(
  '/equipment-assignments/:assignmentId/return',
  requirePermission(Permission.MANAGE_TEAM_OPERATIONS),
  returnEquipment,
);
router.post(
  '/checklist-templates',
  requirePermission(Permission.MANAGE_TEAM_OPERATIONS),
  createChecklistTemplate,
);
router.post(
  '/checklist-runs',
  requirePermission(Permission.MANAGE_TEAM_OPERATIONS),
  createChecklistRun,
);
router.put(
  '/checklist-runs/:runId/items/:itemId',
  requirePermission(Permission.MANAGE_TEAM_OPERATIONS),
  setChecklistItem,
);

export default router;
