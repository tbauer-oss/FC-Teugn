import { asyncRouter } from '../middleware/async-handler';
import {
  approveUser,
  assignParentPlayer,
  removeParentPlayer,
  getMemberPermissions,
  resetMemberPermissions,
  updateMemberPermission,
  createMember,
  createMemberPasswordResetLink,
  sendMemberPushActivationReminder,
  deleteMemberAccount,
  listMembers,
  pendingUsers,
} from '../controllers/admin.controller';
import { requireApproved, requireAuth, requirePermission, requireRoles } from '../middleware/auth';
import { idempotencyMiddleware } from '../middleware/idempotency';
import { Role } from '../types/enums';
import { Permission } from '../security/permissions';
import {
  completeErasure,
  listPrivacyRequests,
  reviewPrivacyRequest,
} from '../controllers/privacy.controller';

const router = asyncRouter();

router.use(requireAuth);
router.use(requireApproved);
router.use(idempotencyMiddleware);
router.use(requirePermission(Permission.MANAGE_MEMBERS));

router.get('/pending-users', pendingUsers);
router.get('/members', listMembers);
router.post('/members', createMember);
router.post(
  '/members/:id/password-reset-link',
  requireRoles([Role.SUPER_ADMIN]),
  createMemberPasswordResetLink,
);
router.post(
  '/members/:id/push-activation-reminder',
  sendMemberPushActivationReminder,
);
router.delete(
  '/members/:id',
  requireRoles([Role.SUPER_ADMIN]),
  deleteMemberAccount,
);
router.post('/approve', approveUser);
router.post('/assign-parent-player', assignParentPlayer);
router.delete(
  '/parent-player-links/:parentId/:playerId',
  requireRoles([Role.SUPER_ADMIN]),
  removeParentPlayer,
);
router.get('/members/:id/permissions', requireRoles([Role.SUPER_ADMIN]), getMemberPermissions);
router.put('/members/:id/permissions', requireRoles([Role.SUPER_ADMIN]), updateMemberPermission);
router.delete('/members/:id/permissions', requireRoles([Role.SUPER_ADMIN]), resetMemberPermissions);
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
