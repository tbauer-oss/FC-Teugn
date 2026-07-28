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
import { requireApproved, requireAuth, requirePermission } from '../middleware/auth';
import { Permission } from '../security/permissions';

const router = Router();

router.use(requireAuth);
router.use(requireApproved);

router.get('/', listEvents);
router.get('/:id', getEvent);
router.post('/', requirePermission(Permission.MANAGE_EVENTS), createEvent);
router.put('/:id', requirePermission(Permission.MANAGE_EVENTS), updateEvent);
router.delete('/:id', requirePermission(Permission.MANAGE_EVENTS), deleteEvent);
router.post('/:id/attendance', setAttendance);
router.post('/:id/attendance/finalize', requirePermission(Permission.MANAGE_EVENTS), finalizeAttendance);
router.put('/:id/match-details', requirePermission(Permission.MANAGE_EVENTS), upsertMatchDetails);
router.put('/:id/squad', requirePermission(Permission.MANAGE_EVENTS), upsertSquad);

export default router;
