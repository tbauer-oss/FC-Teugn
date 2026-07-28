import { Router } from 'express';
import {
  getMatch,
  getTicker,
  listMatches,
  publishSquad,
  tickerCommand,
  undoTickerEvent,
  updateLineup,
  updateMatch,
  updateSquad,
} from '../controllers/matches.controller';
import { requireApproved, requireAuth, requirePermission } from '../middleware/auth';
import { Permission } from '../security/permissions';

const router = Router();

router.use(requireAuth);
router.use(requireApproved);

router.get('/', listMatches);
router.get('/:id', getMatch);
router.put('/:id', requirePermission(Permission.MANAGE_EVENTS), updateMatch);
router.put('/:id/squad', requirePermission(Permission.MANAGE_LINEUPS), updateSquad);
router.post('/:id/squad/publish', requirePermission(Permission.MANAGE_LINEUPS), publishSquad);
router.put('/:id/lineup', requirePermission(Permission.MANAGE_LINEUPS), updateLineup);
router.get('/:id/ticker', getTicker);
router.post(
  '/:id/ticker/events',
  requirePermission(Permission.MANAGE_LIVE_TICKER),
  tickerCommand,
);
router.post(
  '/:id/ticker/undo',
  requirePermission(Permission.MANAGE_LIVE_TICKER),
  undoTickerEvent,
);

export default router;
