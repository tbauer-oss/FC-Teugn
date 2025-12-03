import { Router } from 'express';
import { requireAuth } from '../middleware/auth';
import { changePassword, deleteAccount, me, updateProfile } from '../controllers/users.controller';

const router = Router();

router.get('/me', requireAuth, me);
router.put('/me', requireAuth, updateProfile);
router.post('/me/password', requireAuth, changePassword);
router.delete('/me', requireAuth, deleteAccount);

export default router;
