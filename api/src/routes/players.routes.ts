import { Router } from 'express';
import {
  addDevelopmentNote,
  createEmergencyContact,
  createPlayer,
  deletePlayer,
  getPlayer,
  listPlayers,
  updatePlayer,
  upsertConsent,
  upsertMedicalProfile,
} from '../controllers/players.controller';
import { requireApproved, requireAuth, requirePermission } from '../middleware/auth';
import { Permission } from '../security/permissions';

const router = Router();

router.use(requireAuth);
router.use(requireApproved);

router.get('/', listPlayers);
router.get('/:id', getPlayer);
router.post('/', requirePermission(Permission.MANAGE_PLAYERS), createPlayer);
router.put('/:id', requirePermission(Permission.MANAGE_PLAYERS), updatePlayer);
router.put('/:id/medical', upsertMedicalProfile);
router.post('/:id/emergency-contacts', createEmergencyContact);
router.post(
  '/:id/development-notes',
  requirePermission(Permission.MANAGE_DEVELOPMENT),
  addDevelopmentNote,
);
router.put('/:id/consents/:type', upsertConsent);
router.delete('/:id', requirePermission(Permission.MANAGE_PLAYERS), deletePlayer);

export default router;
