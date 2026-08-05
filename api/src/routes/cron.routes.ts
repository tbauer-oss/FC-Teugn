import { asyncRouter } from '../middleware/async-handler';
import { processScheduledJobs } from '../controllers/cron.controller';

const router = asyncRouter();
router.get('/reminders', processScheduledJobs);
export default router;
