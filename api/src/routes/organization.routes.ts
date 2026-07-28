import { Router } from 'express';
import {
  createTeam,
  organizationContext,
  publicOrganization,
} from '../controllers/organization.controller';
import {
  applySeasonTransition,
  listSeasonTransitions,
  previewSeasonTransition,
} from '../controllers/season-transition.controller';
import {
  approveRuleProfile,
  createRuleProfile,
  listRuleProfiles,
} from '../controllers/rule-profiles.controller';
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
router.get(
  '/rule-profiles',
  requireAuth,
  requireApproved,
  requirePermission(Permission.MANAGE_ORGANIZATION),
  listRuleProfiles,
);
router.post(
  '/rule-profiles',
  requireAuth,
  requireApproved,
  requirePermission(Permission.MANAGE_ORGANIZATION),
  createRuleProfile,
);
router.post(
  '/rule-profiles/:id/approve',
  requireAuth,
  requireApproved,
  requirePermission(Permission.MANAGE_ORGANIZATION),
  approveRuleProfile,
);
router.get(
  '/season-transitions',
  requireAuth,
  requireApproved,
  requirePermission(Permission.MANAGE_ORGANIZATION),
  listSeasonTransitions,
);
router.post(
  '/season-transitions/preview',
  requireAuth,
  requireApproved,
  requirePermission(Permission.MANAGE_ORGANIZATION),
  previewSeasonTransition,
);
router.post(
  '/season-transitions/:id/apply',
  requireAuth,
  requireApproved,
  requirePermission(Permission.MANAGE_ORGANIZATION),
  applySeasonTransition,
);

export default router;
