import { Router } from 'express';
import {
  activeConsentTexts,
  login,
  me,
  register,
} from '../controllers/auth.controller';
import { requireAuth } from '../middleware/auth';

const router = Router();

router.post('/register', register);
router.post('/login', login);
router.get('/consent-texts', activeConsentTexts);
router.get('/me', requireAuth, me);

export default router;
