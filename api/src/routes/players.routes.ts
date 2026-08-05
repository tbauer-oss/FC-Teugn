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
import {
  deletePlayerDocument,
  listPlayerDocuments,
  removePlayerPhoto,
  uploadPlayerDocument,
  uploadPlayerPhoto,
} from '../controllers/player-files.controller';
import { requireApproved, requireAuth, requirePermission } from '../middleware/auth';
import { idempotencyMiddleware } from '../middleware/idempotency';
import { Permission } from '../security/permissions';
import { playerFileUpload } from '../middleware/player-files';
import { asyncHandler } from '../middleware/async-handler';
import {
  downloadConsentEvidence,
  downloadConsentTemplate,
  listConsentTemplates,
  revokePlayerConsent,
  signPlayerConsent,
} from '../controllers/player-consents.controller';

const router = Router();

router.use(requireAuth);
router.use(requireApproved);
router.use(idempotencyMiddleware);

router.get('/', listPlayers);
router.get('/consent-templates', asyncHandler(listConsentTemplates));
router.get(
  '/consent-templates/:type/pdf',
  asyncHandler(downloadConsentTemplate),
);
router.post(
  '/:id/photo',
  playerFileUpload.single('file'),
  asyncHandler(uploadPlayerPhoto),
);
router.delete('/:id/photo', asyncHandler(removePlayerPhoto));
router.get('/:id/documents', listPlayerDocuments);
router.post(
  '/:id/documents',
  playerFileUpload.single('file'),
  asyncHandler(uploadPlayerDocument),
);
router.delete(
  '/:id/documents/:documentId',
  asyncHandler(deletePlayerDocument),
);
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
router.post(
  '/:id/consents/:type/sign',
  asyncHandler(signPlayerConsent),
);
router.post(
  '/:id/consents/:type/revoke',
  asyncHandler(revokePlayerConsent),
);
router.get(
  '/:id/consents/:type/evidence/:evidenceId/pdf',
  asyncHandler(downloadConsentEvidence),
);
router.delete('/:id', requirePermission(Permission.MANAGE_PLAYERS), deletePlayer);

export default router;
