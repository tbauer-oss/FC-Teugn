import { Router } from 'express';
import {
  approveUser,
  assignParentPlayer,
  createMember,
  listMembers,
  pendingUsers,
} from '../controllers/admin.controller';
import { requireApproved, requireAuth, requirePermission } from '../middleware/auth';
import { Permission } from '../security/permissions';
import {
  completeErasure,
  listPrivacyRequests,
  reviewPrivacyRequest,
} from '../controllers/privacy.controller';

const router = Router();

router.use(requireAuth);
router.use(requireApproved);
router.use(requirePermission(Permission.MANAGE_MEMBERS));

router.get('/pending-users', pendingUsers);
router.get('/members', listMembers);
router.post('/members', createMember);
router.post('/approve', approveUser);
router.post('/assign-parent-player', assignParentPlayer);
router.get(
  '/privacy-requests',
  requirePermission(Permission.MANAGE_ORGANIZATION),
  listPrivacyRequests,
);
router.patch(
  '/privacy-requests/:id',
  requirePermission(Permission.MANAGE_ORGANIZATION),
  reviewPrivacyRequest,
);
router.post(
  '/privacy-requests/:id/complete-erasure',
  requirePermission(Permission.MANAGE_ORGANIZATION),
  completeErasure,
);

export default router;
