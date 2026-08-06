import { asyncRouter } from '../middleware/async-handler';
import {
  cancelMatch,
  cancelMatchPreview,
  getMatch,
  getTicker,
  getTickerDelegation,
  listMatches,
  publishSquad,
  resetTicker,
  rescheduleMatch,
  tickerCommand,
  undoTickerEvent,
  updateLineup,
  updateMatch,
  updateSquad,
  updateTickerDelegation,
} from '../controllers/matches.controller';
import { requireApproved, requireAuth, requirePermission } from '../middleware/auth';
import { idempotencyMiddleware } from '../middleware/idempotency';
import { Permission } from '../security/permissions';
import { deleteEvent } from '../controllers/events.controller';

const router = asyncRouter();

router.use(requireAuth);
router.use(requireApproved);
router.use(idempotencyMiddleware);

router.get('/', listMatches);
router.get('/:id', getMatch);
router.get(
  '/:id/cancel-preview',
  requirePermission(Permission.MATCH_CANCEL),
  cancelMatchPreview,
);
router.post(
  '/:id/cancel',
  requirePermission(Permission.MATCH_CANCEL),
  cancelMatch,
);
router.delete(
  '/:id',
  requirePermission(Permission.MATCH_DELETE),
  (req, res) => {
    req.query.permanent = 'true';
    return deleteEvent(req, res);
  },
);
router.put('/:id', requirePermission(Permission.MANAGE_EVENTS), updateMatch);
router.patch(
  '/:id/reschedule',
  requirePermission(Permission.MATCH_RESCHEDULE),
  rescheduleMatch,
);
router.put('/:id/squad', requirePermission(Permission.MANAGE_LINEUPS), updateSquad);
router.post('/:id/squad/publish', requirePermission(Permission.MANAGE_LINEUPS), publishSquad);
router.put('/:id/lineup', requirePermission(Permission.MANAGE_LINEUPS), updateLineup);
router.get('/:id/ticker', getTicker);
router.get('/:id/ticker/delegation', getTickerDelegation);
router.put('/:id/ticker/delegation', updateTickerDelegation);
router.post('/:id/ticker/events', tickerCommand);
router.post('/:id/ticker/undo', undoTickerEvent);
router.post(
  '/:id/ticker/reset',
  requirePermission(Permission.MANAGE_LIVE_TICKER),
  resetTicker,
);

export default router;
