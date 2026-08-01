import { Router } from 'express';
import {
  getNotificationPreferences,
  grantPushConsent,
  listNotifications,
  listPushSubscriptions,
  markAllNotificationsRead,
  markNotificationRead,
  notificationConfiguration,
  registerPushSubscription,
  removeCurrentPushSubscription,
  removePushSubscription,
  saveNotificationPreferences,
  testPushBroadcast,
} from '../controllers/notifications.controller';
import { requireApproved, requireAuth, requireRoles } from '../middleware/auth';
import { Role } from '../types/enums';

const router = Router();
router.use(requireAuth);
router.use(requireApproved);
router.get('/', listNotifications);
router.post('/admin/test-push', requireRoles([Role.SUPER_ADMIN]), testPushBroadcast);
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
