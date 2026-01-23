import { Router } from 'express';
import { approveUser, assignParentPlayer, pendingUsers } from '../controllers/admin.controller';
import { requireApproved, requireAuth, requireRoles } from '../middleware/auth';
import { Role } from '../types/enums';

const router = Router();

router.use(requireAuth);
router.use(requireApproved);
router.use(requireRoles([Role.TRAINER_ADMIN, Role.TRAINER]));

router.get('/pending-users', pendingUsers);
router.post('/approve', approveUser);
router.post('/assign-parent-player', assignParentPlayer);

export default router;
