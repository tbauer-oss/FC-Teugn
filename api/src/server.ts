import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import authRoutes from './routes/auth.routes';
import playersRoutes from './routes/players.routes';
import eventsRoutes from './routes/events.routes';
import adminRoutes from './routes/admin.routes';
import organizationRoutes from './routes/organization.routes';
import { errorHandler } from './middleware/errorHandler';

dotenv.config();

const app = express();

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
app.use(express.json());

app.get('/', (_req, res) => res.json({ status: 'ok' }));

app.use('/auth', authRoutes);
app.use('/players', playersRoutes);
app.use('/events', eventsRoutes);
app.use('/admin', adminRoutes);
app.use('/organization', organizationRoutes);

app.use(errorHandler);

export default app;
