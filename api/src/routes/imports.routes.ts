import { asyncRouter } from '../middleware/async-handler';
import {
  applyCompetitionImport,
  listCompetitionImports,
  previewCompetitionImport,
} from '../controllers/imports.controller';
import {
  requireApproved,
  requireAuth,
  requirePermission,
} from '../middleware/auth';
import { idempotencyMiddleware } from '../middleware/idempotency';
import { Permission } from '../security/permissions';

const router = asyncRouter();
router.use(requireAuth);
router.use(requireApproved);
router.use(idempotencyMiddleware);
router.get('/', requirePermission(Permission.MANAGE_IMPORTS), listCompetitionImports);
router.post(
  '/competition/preview',
  requirePermission(Permission.MANAGE_IMPORTS),
  previewCompetitionImport,
);
router.post(
  '/competition/:id/apply',
  requirePermission(Permission.MANAGE_IMPORTS),
  applyCompetitionImport,
);

export default router;
