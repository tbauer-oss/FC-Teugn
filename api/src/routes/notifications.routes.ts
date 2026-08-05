import { asyncRouter } from '../middleware/async-handler';
import {
  getNotificationPreferences,
  grantPushConsent,
  deleteAdminPushDevice,
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
router.get('/admin/devices', requireRoles([Role.SUPER_ADMIN]), listAdminPushDevices);
router.patch(
  '/admin/devices/:id',
  requireRoles([Role.SUPER_ADMIN]),
  setAdminPushDeviceState,
);
router.delete(
  '/admin/devices/:id',
  requireRoles([Role.SUPER_ADMIN]),
  deleteAdminPushDevice,
);
router.post('/read-all', markAllNotificationsRead);
router.post('/:id/read', markNotificationRead);
router.get('/settings/configuration', notificationConfiguration);
router.get('/settings/preferences', getNotificationPreferences);
router.put('/settings/preferences', saveNotificationPreferences);
router.get('/settings/subscriptions', listPushSubscriptions);
router.post('/settings/subscriptions', registerPushSubscription);
router.delete('/settings/subscriptions', removeCurrentPushSubscription);
router.delete('/settings/subscriptions/:id', removePushSubscription);
router.post('/settings/push-consent', grantPushConsent);

export default router;
