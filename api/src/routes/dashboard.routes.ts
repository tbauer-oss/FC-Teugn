import {
  parentConsentAttention,
  parentDashboardSummary,
  trainerDashboardSummary,
} from '../controllers/dashboard.controller';
import { requireApproved, requireAuth } from '../middleware/auth';
import { asyncRouter } from '../middleware/async-handler';

const router = asyncRouter();
router.use(requireAuth, requireApproved);
router.get('/parent', parentDashboardSummary);
router.get('/parent/consent-attention', parentConsentAttention);
router.get('/trainer', trainerDashboardSummary);

export default router;
