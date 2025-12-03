import { Router } from 'express';
import { requireAuth, requireRole } from '../middleware/auth';
import { Role } from '@prisma/client';
import {
  listEvents,
  createEvent,
  updateEvent,
  deleteEvent,
  setEventRSVP,
} from '../controllers/events.controller';

const router = Router();

router.get('/', requireAuth, listEvents);
router.post('/', requireAuth, requireRole(Role.COACH), createEvent);
router.put('/:eventId', requireAuth, requireRole(Role.COACH), updateEvent);
router.delete('/:eventId', requireAuth, requireRole(Role.COACH), deleteEvent);
router.post('/:eventId/rsvp', requireAuth, setEventRSVP);

export default router;
