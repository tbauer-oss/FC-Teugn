import { Router } from 'express';
import { requireAuth, requireRole } from '../middleware/auth';
import { Role } from '@prisma/client';
import {
  listMatches,
  createMatch,
  updateMatch,
  deleteMatch,
  setMatchRSVP,
  saveLineup,
  toggleGoal,
} from '../controllers/matches.controller';

const router = Router();

router.get('/', requireAuth, listMatches);
router.post('/', requireAuth, requireRole(Role.COACH), createMatch);
router.put('/:matchId', requireAuth, requireRole(Role.COACH), updateMatch);
router.delete('/:matchId', requireAuth, requireRole(Role.COACH), deleteMatch);

router.post('/:matchId/rsvp', requireAuth, setMatchRSVP);
router.post('/:matchId/lineups', requireAuth, requireRole(Role.COACH), saveLineup);
router.post('/:matchId/goals/toggle', requireAuth, requireRole(Role.COACH), toggleGoal);

export default router;
