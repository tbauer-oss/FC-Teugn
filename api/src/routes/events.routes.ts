import { Router } from 'express';
import {
  createEvent,
  deleteEvent,
  finalizeAttendance,
  getEvent,
  listEvents,
  setAttendance,
  updateEvent,
  upsertMatchDetails,
  upsertSquad,
} from '../controllers/events.controller';
import { requireApproved, requireAuth, requireRoles } from '../middleware/auth';
import { Role } from '../types/enums';

const router = Router();

router.use(requireAuth);
router.use(requireApproved);

router.get('/', listEvents);
router.get('/:id', getEvent);
router.post('/', requireRoles([Role.TRAINER_ADMIN, Role.TRAINER]), createEvent);
router.put('/:id', requireRoles([Role.TRAINER_ADMIN, Role.TRAINER]), updateEvent);
router.delete('/:id', requireRoles([Role.TRAINER_ADMIN, Role.TRAINER]), deleteEvent);
router.post('/:id/attendance', setAttendance);
router.post('/:id/attendance/finalize', requireRoles([Role.TRAINER_ADMIN, Role.TRAINER]), finalizeAttendance);
router.put('/:id/match-details', requireRoles([Role.TRAINER_ADMIN, Role.TRAINER]), upsertMatchDetails);
router.put('/:id/squad', requireRoles([Role.TRAINER_ADMIN, Role.TRAINER]), upsertSquad);

export default router;
