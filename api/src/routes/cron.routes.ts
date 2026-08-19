import { asyncRouter } from '../middleware/async-handler';
import {
  processRegularTrainingJobs,
  processScheduledJobs,
} from '../controllers/cron.controller';

const router = asyncRouter();
router.get('/reminders', processScheduledJobs);
router.get('/regular-trainings', processRegularTrainingJobs);
export default router;
