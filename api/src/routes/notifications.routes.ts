import { asyncRouter } from '../middleware/async-handler';
import {
  getNotificationPreferences,
  grantPushConsent,
  deleteAllDisabledAdminPushDevices,
  deleteAdminPushDevice,
  deleteReadNotifications,
  deleteNotification,
  listAdminPushDevices,
  listNotifications,
  listPushSubscriptions,
  markAllNotificationsRead,
  markNotificationRead,
  notificationConfiguration,
  registerPushSubscription,
  removeCurrentPushSubscription,
  removePushSubscription,
  saveNotificationPreferences,
  setAdminPushDeviceState,
  testPushBroadcast,
  testOwnPushScenario,
} from '../controllers/notifications.controller';
import { requireApproved, requireAuth, requireRoles } from '../middleware/auth';
import { idempotencyMiddleware } from '../middleware/idempotency';
import { Role } from '../types/enums';

const router = asyncRouter();
router.use(requireAuth);
router.use(requireApproved);
router.use(idempotencyMiddleware);
router.get('/', listNotifications);
router.post('/admin/test-push', requireRoles([Role.SUPER_ADMIN]), testPushBroadcast);
router.post(
  '/admin/test-push/self',
  requireRoles([Role.SUPER_ADMIN]),
  testOwnPushScenario,
);
router.get('/admin/devices', requireRoles([Role.SUPER_ADMIN]), listAdminPushDevices);
router.patch(
  '/admin/devices/:id',
  requireRoles([Role.SUPER_ADMIN]),
  setAdminPushDeviceState,
);
router.delete(
  '/admin/devices/disabled',
  requireRoles([Role.SUPER_ADMIN]),
  deleteAllDisabledAdminPushDevices,
);
router.delete(
  '/admin/devices/:id',
  requireRoles([Role.SUPER_ADMIN]),
  deleteAdminPushDevice,
);
router.post('/read-all', markAllNotificationsRead);
router.delete('/read', deleteReadNotifications);
router.post('/:id/read', markNotificationRead);
router.delete(
  '/:id',
  requireRoles([
    Role.SUPER_ADMIN,
    Role.CLUB_ADMIN,
    Role.YOUTH_DIRECTOR,
    Role.COACH,
    Role.ASSISTANT_COACH,
    Role.TEAM_MANAGER,
    Role.TRAINER_ADMIN,
    Role.TRAINER,
  ]),
  deleteNotification,
);
router.get('/settings/configuration', notificationConfiguration);
router.get('/settings/preferences', getNotificationPreferences);
router.put('/settings/preferences', saveNotificationPreferences);
router.get('/settings/subscriptions', listPushSubscriptions);
router.post('/settings/subscriptions', registerPushSubscription);
router.delete('/settings/subscriptions', removeCurrentPushSubscription);
router.delete('/settings/subscriptions/:id', removePushSubscription);
router.post('/settings/push-consent', grantPushConsent);

export default router;
