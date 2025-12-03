import { Router } from 'express';
import { requireAuth, requireRole } from '../middleware/auth';
import { Role } from '../types/enums';
import { getLeagueTables, createLeagueTable } from '../controllers/league.controller';

const router = Router();

router.get('/', requireAuth, getLeagueTables);
router.post('/', requireAuth, requireRole(Role.COACH), createLeagueTable);

export default router;
