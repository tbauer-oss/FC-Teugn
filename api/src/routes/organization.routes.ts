import { Router } from 'express';
import {
  createTeam,
  organizationContext,
  publicOrganization,
} from '../controllers/organization.controller';
import { requireApproved, requireAuth, requirePermission } from '../middleware/auth';
import { Permission } from '../security/permissions';

const router = Router();

router.get('/public', publicOrganization);
router.get('/context', requireAuth, requireApproved, organizationContext);
router.post(
  '/teams',
  requireAuth,
  requireApproved,
  requirePermission(Permission.MANAGE_ORGANIZATION),
  createTeam,
);

export default router;
