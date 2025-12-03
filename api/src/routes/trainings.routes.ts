import { Router } from 'express';
import { requireAuth, requireRole } from '../middleware/auth';
import { Role } from '../types/enums';
import {
  listTrainings,
  createTraining,
  updateTraining,
  deleteTraining,
} from '../controllers/trainings.controller';

const router = Router();

router.get('/', requireAuth, listTrainings);
router.post('/', requireAuth, requireRole(Role.COACH), createTraining);
router.put('/:trainingId', requireAuth, requireRole(Role.COACH), updateTraining);
router.delete('/:trainingId', requireAuth, requireRole(Role.COACH), deleteTraining);

export default router;
