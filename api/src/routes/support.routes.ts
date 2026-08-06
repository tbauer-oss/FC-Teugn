import { asyncRouter } from '../middleware/async-handler';
import { requireApproved, requireAuth } from '../middleware/auth';
import { playerFileUpload } from '../middleware/player-files';
import {
  createSupportTicket,
  getSupportTicket,
  listSupportTickets,
  replySupportTicket,
  updateSupportStatus,
} from '../controllers/support.controller';

const router = asyncRouter();
router.use(requireAuth);
router.use(requireApproved);

router.get('/', listSupportTickets);
router.post('/', playerFileUpload.single('file'), createSupportTicket);
router.get('/:id', getSupportTicket);
router.post('/:id/messages', replySupportTicket);
router.patch('/:id/status', updateSupportStatus);

export default router;
