import { Router } from 'express';
import {
  archiveExercise,
  getTraining,
  listExercises,
  listTrainings,
  recordTrainingAttendance,
  saveExercise,
  saveTrainingPlan,
} from '../controllers/trainings.controller';
import { requireApproved, requireAuth, requirePermission } from '../middleware/auth';
import { Permission } from '../security/permissions';

const router = Router();
router.use(requireAuth);
router.use(requireApproved);
router.get('/', requirePermission(Permission.MANAGE_TRAINING), listTrainings);
router.get('/exercises', requirePermission(Permission.MANAGE_TRAINING), listExercises);
router.post('/exercises', requirePermission(Permission.MANAGE_TRAINING), saveExercise);
router.put(
  '/exercises/:exerciseId',
  requirePermission(Permission.MANAGE_TRAINING),
  saveExercise,
);
router.delete(
  '/exercises/:exerciseId',
  requirePermission(Permission.MANAGE_TRAINING),
  archiveExercise,
);
router.get('/:id', requirePermission(Permission.MANAGE_TRAINING), getTraining);
router.put('/:id/plan', requirePermission(Permission.MANAGE_TRAINING), saveTrainingPlan);
router.put(
  '/:id/attendance',
  requirePermission(Permission.MANAGE_TRAINING),
  recordTrainingAttendance,
);

export default router;
