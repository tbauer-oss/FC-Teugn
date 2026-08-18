import { asyncRouter } from '../middleware/async-handler';
import {
  archiveAnnouncement,
  getAnnouncement,
  listFamilyContacts,
  listAnnouncements,
  markAnnouncementRead,
  permanentlyDeleteAnnouncement,
  publishAnnouncement,
  saveAnnouncement,
  sendFamilyContact,
} from '../controllers/communications.controller';
import {
  requireApproved,
  requireAuth,
  requirePermission,
  requireRoles,
} from '../middleware/auth';
import { idempotencyMiddleware } from '../middleware/idempotency';
import { Permission } from '../security/permissions';
import { Role } from '../types/enums';

const router = asyncRouter();
router.use(requireAuth);
router.use(requireApproved);
router.use(idempotencyMiddleware);
router.get('/family-contact', listFamilyContacts);
router.post('/family-contact', sendFamilyContact);
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
  '/:id/permanent',
  requireRoles([Role.SUPER_ADMIN]),
  permanentlyDeleteAnnouncement,
);
router.delete(
  '/:id',
  requirePermission(Permission.SEND_ANNOUNCEMENTS),
  archiveAnnouncement,
);
router.post('/:id/read', markAnnouncementRead);

export default router;
