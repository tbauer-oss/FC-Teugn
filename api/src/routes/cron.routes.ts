import { Router } from 'express';
import { processScheduledJobs } from '../controllers/cron.controller';

const router = Router();
router.get('/reminders', processScheduledJobs);
export default router;
