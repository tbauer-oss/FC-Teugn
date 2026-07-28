import { Router } from 'express';
import {
  recalculateMatch,
  statisticsOverview,
} from '../controllers/statistics.controller';
import { requireApproved, requireAuth, requirePermission } from '../middleware/auth';
import { Permission } from '../security/permissions';

const router = Router();
router.use(requireAuth);
router.use(requireApproved);
router.get('/', requirePermission(Permission.VIEW_PLAYER_STATS), statisticsOverview);
router.post(
  '/matches/:matchId/recalculate',
  requirePermission(Permission.MANAGE_STATISTICS),
  recalculateMatch,
);

export default router;
