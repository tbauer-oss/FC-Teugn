import { Router } from 'express';
import { requireAuth, requireRole } from '../middleware/auth';
import { Role } from '../types/enums';
import {
  listPlayers,
  createPlayer,
  updatePlayer,
  deletePlayer,
} from '../controllers/players.controller';

const router = Router();

router.get('/', requireAuth, listPlayers);
router.post('/', requireAuth, requireRole(Role.COACH), createPlayer);
router.put('/:playerId', requireAuth, requireRole(Role.COACH), updatePlayer);
router.delete('/:playerId', requireAuth, requireRole(Role.COACH), deletePlayer);

export default router;
