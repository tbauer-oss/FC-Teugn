import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import authRoutes from './routes/auth.routes';
import playersRoutes from './routes/players.routes';
import eventsRoutes from './routes/events.routes';
import adminRoutes from './routes/admin.routes';
import organizationRoutes from './routes/organization.routes';
import matchesRoutes from './routes/matches.routes';
import statisticsRoutes from './routes/statistics.routes';
import trainingsRoutes from './routes/trainings.routes';
import communicationsRoutes from './routes/communications.routes';
import notificationsRoutes from './routes/notifications.routes';
import importsRoutes from './routes/imports.routes';
import { errorHandler } from './middleware/errorHandler';
import { authRateLimit } from './middleware/rate-limit';

dotenv.config();

const app = express();
app.set('trust proxy', 1);

const defaultAllowedOrigins = [
  'https://fcteugnapp.vercel.app',
  'https://fc-teugn.vercel.app',
  'http://localhost:3000',
  'http://localhost:4000',
];

const envAllowedOrigins = process.env.CORS_ORIGINS?.split(',')
  .map((o) => o.trim())
  .filter(Boolean);
const allowAllOrigins = envAllowedOrigins?.includes('*') ?? false;
const allowedOrigins = Array.from(
  new Set([...(envAllowedOrigins ?? []).filter((origin) => origin !== '*'), ...defaultAllowedOrigins]),
);

function isAllowedFrontendOrigin(origin: string) {
  if (allowedOrigins.includes(origin)) {
    return true;
  }

  try {
    const { protocol, hostname } = new URL(origin);
    const isFcTeugnVercelDeployment =
      /^(?:fc-teugn|fcteugnapp)(?:-[a-z0-9-]+)?-tobis-projects-7d669891\.vercel\.app$/.test(
        hostname,
      );

    return protocol === 'https:' && isFcTeugnVercelDeployment;
  } catch {
    return false;
  }
}

app.use(
  cors({
    origin: (origin, callback) => {
      if (!origin) {
        callback(null, true);
        return;
      }

      if (allowAllOrigins || allowedOrigins.length === 0 || isAllowedFrontendOrigin(origin)) {
        callback(null, true);
        return;
      }

      callback(null, false);
    },
    credentials: true,
  }),
);
app.disable('x-powered-by');
app.use(express.json({ limit: '1mb' }));

app.get('/', (_req, res) => res.json({ status: 'ok' }));

app.use('/auth', authRateLimit, authRoutes);
app.use('/players', playersRoutes);
app.use('/events', eventsRoutes);
app.use('/admin', adminRoutes);
app.use('/organization', organizationRoutes);
app.use('/matches', matchesRoutes);
app.use('/statistics', statisticsRoutes);
app.use('/trainings', trainingsRoutes);
app.use('/communications', communicationsRoutes);
app.use('/notifications', notificationsRoutes);
app.use('/imports', importsRoutes);

app.use(errorHandler);

export default app;
