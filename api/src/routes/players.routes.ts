import { Router } from 'express';
import { createPlayer, deletePlayer, getPlayer, listPlayers, updatePlayer } from '../controllers/players.controller';
import { requireApproved, requireAuth, requireRoles } from '../middleware/auth';
import { Role } from '../types/enums';

const router = Router();

router.use(requireAuth);
router.use(requireApproved);

router.get('/', listPlayers);
router.get('/:id', getPlayer);
router.post('/', requireRoles([Role.TRAINER_ADMIN, Role.TRAINER]), createPlayer);
router.put('/:id', requireRoles([Role.TRAINER_ADMIN, Role.TRAINER]), updatePlayer);
router.delete('/:id', requireRoles([Role.TRAINER_ADMIN, Role.TRAINER]), deletePlayer);

export default router;
