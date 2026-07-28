import { Router } from 'express';
import {
  getNotificationPreferences,
  listNotifications,
  listPushSubscriptions,
  markAllNotificationsRead,
  markNotificationRead,
  notificationConfiguration,
  registerPushSubscription,
  removePushSubscription,
  saveNotificationPreferences,
} from '../controllers/notifications.controller';
import { requireApproved, requireAuth } from '../middleware/auth';

const router = Router();
router.use(requireAuth);
router.use(requireApproved);
router.get('/', listNotifications);
router.post('/read-all', markAllNotificationsRead);
router.post('/:id/read', markNotificationRead);
router.get('/settings/configuration', notificationConfiguration);
router.get('/settings/preferences', getNotificationPreferences);
router.put('/settings/preferences', saveNotificationPreferences);
router.get('/settings/subscriptions', listPushSubscriptions);
router.post('/settings/subscriptions', registerPushSubscription);
router.delete('/settings/subscriptions/:id', removePushSubscription);

export default router;
