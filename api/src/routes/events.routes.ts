import { Router } from 'express';
import {
  calendarSubscription,
  createCarpoolOffer,
  createEvent,
  deleteEvent,
  finalizeAttendance,
  getEvent,
  listEvents,
  publicCalendarSubscription,
  recordActualAttendance,
  requestCarpoolSeat,
  sendAttendanceReminders,
  setAttendance,
  updateCarpoolPassenger,
  updateEvent,
  upsertMatchDetails,
  upsertSquad,
} from '../controllers/events.controller';
import { requireApproved, requireAuth, requirePermission } from '../middleware/auth';
import {
  getEmergencyView,
  requestEmergencyAccess,
} from '../controllers/emergency.controller';
import { sensitiveActionRateLimit } from '../middleware/rate-limit';
import { Permission } from '../security/permissions';
import {
  checkPitchConflicts,
  listPitchConflictRequests,
  respondToPitchConflictRequest,
} from '../controllers/pitch-conflicts.controller';

const router = Router();

router.get('/subscription/:token.ics', publicCalendarSubscription);

router.use(requireAuth);
router.use(requireApproved);

router.get('/', listEvents);
router.get('/pitch-conflict-requests/list', listPitchConflictRequests);
router.post(
  '/pitch-conflicts/check',
  requirePermission(Permission.MANAGE_EVENTS),
  checkPitchConflicts,
);
router.patch(
  '/pitch-conflict-requests/:requestId',
  respondToPitchConflictRequest,
);
router.post('/calendar-subscription', calendarSubscription);
router.post(
  '/:id/emergency-access',
  requirePermission(Permission.VIEW_SENSITIVE_PLAYER),
  sensitiveActionRateLimit,
  requestEmergencyAccess,
);
router.get(
  '/:id/emergency-view',
  requirePermission(Permission.VIEW_SENSITIVE_PLAYER),
  getEmergencyView,
);
router.get('/:id', getEvent);
router.post('/', requirePermission(Permission.MANAGE_EVENTS), createEvent);
router.put('/:id', requirePermission(Permission.MANAGE_EVENTS), updateEvent);
router.delete('/:id', requirePermission(Permission.MANAGE_EVENTS), deleteEvent);
router.post('/:id/attendance', setAttendance);
router.post(
  '/:id/attendance/finalize',
  requirePermission(Permission.MANAGE_EVENTS),
  finalizeAttendance,
);
router.put(
  '/:id/attendance/actual',
  requirePermission(Permission.MANAGE_EVENTS),
  recordActualAttendance,
);
router.post(
  '/:id/attendance/reminders',
  requirePermission(Permission.MANAGE_EVENTS),
  sendAttendanceReminders,
);
router.post('/:id/carpool-offers', createCarpoolOffer);
router.post('/:id/carpool-offers/:offerId/passengers', requestCarpoolSeat);
router.patch(
  '/:id/carpool-offers/:offerId/passengers/:passengerId',
  updateCarpoolPassenger,
);
router.put('/:id/match-details', requirePermission(Permission.MANAGE_EVENTS), upsertMatchDetails);
router.put('/:id/squad', requirePermission(Permission.MANAGE_EVENTS), upsertSquad);

export default router;
