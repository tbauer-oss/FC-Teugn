import { asyncRouter } from '../middleware/async-handler';
import {
  activeConsentTexts,
  login,
  logout,
  logoutAll,
  me,
  refresh,
  register,
  requestPasswordReset,
  exchangePasswordReset,
  confirmPasswordReset,
} from '../controllers/auth.controller';
import { requireAuth } from '../middleware/auth';
import {
  exportPersonalData,
  listOwnPrivacyRequests,
  requestDataSubjectRight,
  requestErasure,
} from '../controllers/privacy.controller';

const router = asyncRouter();

router.post('/register', register);
router.post('/login', login);
router.post('/password-reset/request', requestPasswordReset);
router.post('/password-reset/exchange', exchangePasswordReset);
router.post('/password-reset/confirm', confirmPasswordReset);
router.post('/refresh', refresh);
router.post('/logout', logout);
router.post('/logout-all', requireAuth, logoutAll);
router.get('/consent-texts', activeConsentTexts);
router.get('/me', requireAuth, me);
router.get('/privacy/export', requireAuth, exportPersonalData);
router.get('/privacy/requests', requireAuth, listOwnPrivacyRequests);
router.post('/privacy/requests', requireAuth, requestDataSubjectRight);
router.post('/privacy/erasure-requests', requireAuth, requestErasure);

export default router;
