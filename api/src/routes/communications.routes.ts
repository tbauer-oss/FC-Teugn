import { Router } from 'express';
import {
  archiveAnnouncement,
  getAnnouncement,
  listAnnouncements,
  markAnnouncementRead,
  publishAnnouncement,
  saveAnnouncement,
} from '../controllers/communications.controller';
import { requireApproved, requireAuth, requirePermission } from '../middleware/auth';
import { Permission } from '../security/permissions';

const router = Router();
router.use(requireAuth);
router.use(requireApproved);
router.get('/', listAnnouncements);
router.get('/:id', getAnnouncement);
router.post('/', requirePermission(Permission.SEND_ANNOUNCEMENTS), saveAnnouncement);
router.put('/:id', requirePermission(Permission.SEND_ANNOUNCEMENTS), saveAnnouncement);
router.post(
  '/:id/publish',
  requirePermission(Permission.SEND_ANNOUNCEMENTS),
  publishAnnouncement,
);
router.delete(
  '/:id',
  requirePermission(Permission.SEND_ANNOUNCEMENTS),
  archiveAnnouncement,
);
router.post('/:id/read', markAnnouncementRead);

export default router;
