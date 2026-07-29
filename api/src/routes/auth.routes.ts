import { Router } from 'express';
import {
  activeConsentTexts,
  login,
  logout,
  logoutAll,
  me,
  refresh,
  register,
} from '../controllers/auth.controller';
import { requireAuth } from '../middleware/auth';
import {
  exportPersonalData,
  listOwnPrivacyRequests,
  requestErasure,
} from '../controllers/privacy.controller';

const router = Router();

router.post('/register', register);
router.post('/login', login);
router.post('/refresh', refresh);
router.post('/logout', logout);
router.post('/logout-all', requireAuth, logoutAll);
router.get('/consent-texts', activeConsentTexts);
router.get('/me', requireAuth, me);
router.get('/privacy/export', requireAuth, exportPersonalData);
router.get('/privacy/requests', requireAuth, listOwnPrivacyRequests);
router.post('/privacy/erasure-requests', requireAuth, requestErasure);

export default router;
