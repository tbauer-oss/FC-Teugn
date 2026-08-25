import { asyncRouter } from '../middleware/async-handler';
import {
  calendarSubscription,
  cancelRegularTrainingOccurrence,
  createCarpoolOffer,
  createCarpoolNeeds,
  createEvent,
  deleteEvent,
  deleteCarpoolNeed,
  deleteCarpoolOffer,
  finalizeAttendance,
  getEvent,
  listEvents,
  listPersonalResponses,
  publicCalendarSubscription,
  recordActualAttendance,
  requestCarpoolSeat,
  attendanceReminderStatus,
  sendAttendanceReminders,
  setAttendance,
  setRegularTrainingAttendancePreference,
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
import { idempotencyMiddleware } from '../middleware/idempotency';
import {
  checkPitchConflicts,
  listPitchConflictRequests,
  respondToPitchConflictRequest,
} from '../controllers/pitch-conflicts.controller';

const router = asyncRouter();

router.get('/subscription/:token.ics', publicCalendarSubscription);

router.use(requireAuth);
router.use(requireApproved);
router.use(idempotencyMiddleware);

router.get('/', listEvents);
router.get('/personal-responses/list', listPersonalResponses);
router.post(
  '/regular-training-occurrences/cancel',
  requirePermission(Permission.CANCEL_TRAINING_OCCURRENCE),
  cancelRegularTrainingOccurrence,
);
router.get(
  '/pitch-conflict-requests/list',
  requirePermission(Permission.MANAGE_EVENTS),
  listPitchConflictRequests,
);
router.post(
  '/pitch-conflicts/check',
  requirePermission(Permission.MANAGE_EVENTS),
  checkPitchConflicts,
);
router.patch(
  '/pitch-conflict-requests/:requestId',
  requirePermission(Permission.MANAGE_EVENTS),
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
// Die konkrete Termin-/Spielberechtigung und der Objektbereich werden im
// Controller geprüft. Dadurch funktionieren auch individuelle Rechte, ohne
// dass ein allgemeines MANAGE_EVENTS-Recht als versteckte Voraussetzung wirkt.
router.delete('/:id', deleteEvent);
router.post(
  '/:id/attendance/regular-series',
  setRegularTrainingAttendancePreference,
);
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
router.get(
  '/:id/attendance/reminders/status',
  requirePermission(Permission.MANAGE_EVENTS),
  attendanceReminderStatus,
);
router.post('/:id/carpool-offers', createCarpoolOffer);
router.delete('/:id/carpool-offers/:offerId', deleteCarpoolOffer);
router.post('/:id/carpool-needs', createCarpoolNeeds);
router.delete('/:id/carpool-needs/:needId', deleteCarpoolNeed);
router.post('/:id/carpool-offers/:offerId/passengers', requestCarpoolSeat);
router.patch(
  '/:id/carpool-offers/:offerId/passengers/:passengerId',
  updateCarpoolPassenger,
);
router.put('/:id/match-details', requirePermission(Permission.MANAGE_EVENTS), upsertMatchDetails);
router.put('/:id/squad', requirePermission(Permission.MANAGE_EVENTS), upsertSquad);

export default router;
