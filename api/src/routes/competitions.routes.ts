import { asyncRouter } from '../middleware/async-handler';
import {
  archiveLeague,
  archiveOpponent,
  deleteLeagueMatch,
  listLeagues,
  listOpponents,
  removeOpponentLogo,
  saveLeague,
  saveLeagueMatch,
  saveOpponent,
  uploadOpponentLogo,
} from '../controllers/competitions.controller';
import { requireApproved, requireAuth, requirePermission } from '../middleware/auth';
import { idempotencyMiddleware } from '../middleware/idempotency';
import { playerFileUpload } from '../middleware/player-files';
import { Permission } from '../security/permissions';

const router = asyncRouter();
router.use(requireAuth);
router.use(requireApproved);
router.use(idempotencyMiddleware);
router.get('/opponents', listOpponents);
router.post('/opponents', requirePermission(Permission.MANAGE_EVENTS), saveOpponent);
router.put('/opponents/:id', requirePermission(Permission.MANAGE_EVENTS), saveOpponent);
router.delete('/opponents/:id', requirePermission(Permission.MANAGE_EVENTS), archiveOpponent);
router.post(
  '/opponents/:id/logo',
  requirePermission(Permission.MANAGE_EVENTS),
  playerFileUpload.single('file'),
  uploadOpponentLogo,
);
router.delete(
  '/opponents/:id/logo',
  requirePermission(Permission.MANAGE_EVENTS),
  removeOpponentLogo,
);
router.get('/leagues', listLeagues);
router.post('/leagues', requirePermission(Permission.MANAGE_EVENTS), saveLeague);
router.put('/leagues/:id', requirePermission(Permission.MANAGE_EVENTS), saveLeague);
router.delete('/leagues/:id', requirePermission(Permission.MANAGE_EVENTS), archiveLeague);
router.post(
  '/leagues/:leagueId/matches',
  requirePermission(Permission.MANAGE_EVENTS),
  saveLeagueMatch,
);
router.put(
  '/leagues/:leagueId/matches/:matchId',
  requirePermission(Permission.LEAGUE_MATCH_RESCHEDULE),
  saveLeagueMatch,
);
router.delete(
  '/leagues/:leagueId/matches/:matchId',
  requirePermission(Permission.LEAGUE_MATCH_DELETE),
  deleteLeagueMatch,
);

export default router;
