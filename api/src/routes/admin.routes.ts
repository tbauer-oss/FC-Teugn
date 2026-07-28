import { Router } from 'express';
import { approveUser, assignParentPlayer, pendingUsers } from '../controllers/admin.controller';
import { requireApproved, requireAuth, requirePermission } from '../middleware/auth';
import { Permission } from '../security/permissions';

const router = Router();

router.use(requireAuth);
router.use(requireApproved);
router.use(requirePermission(Permission.MANAGE_MEMBERS));

router.get('/pending-users', pendingUsers);
router.post('/approve', approveUser);
router.post('/assign-parent-player', assignParentPlayer);

export default router;
