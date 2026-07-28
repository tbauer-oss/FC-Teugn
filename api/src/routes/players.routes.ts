import { Router } from 'express';
import { createPlayer, deletePlayer, getPlayer, listPlayers, updatePlayer } from '../controllers/players.controller';
import { requireApproved, requireAuth, requirePermission } from '../middleware/auth';
import { Permission } from '../security/permissions';

const router = Router();

router.use(requireAuth);
router.use(requireApproved);

router.get('/', listPlayers);
router.get('/:id', getPlayer);
router.post('/', requirePermission(Permission.MANAGE_PLAYERS), createPlayer);
router.put('/:id', requirePermission(Permission.MANAGE_PLAYERS), updatePlayer);
router.delete('/:id', requirePermission(Permission.MANAGE_PLAYERS), deletePlayer);

export default router;
