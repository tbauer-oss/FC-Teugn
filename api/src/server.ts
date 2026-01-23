import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import authRoutes from './routes/auth.routes';
import playersRoutes from './routes/players.routes';
import eventsRoutes from './routes/events.routes';
import adminRoutes from './routes/admin.routes';
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
const allowedOrigins = Array.from(new Set([...(envAllowedOrigins ?? []), ...defaultAllowedOrigins]));

app.use(
  cors({
    origin: (origin, callback) => {
      if (!origin) {
        callback(null, true);
        return;
      }

      if (allowedOrigins.length === 0 || allowedOrigins.includes(origin)) {
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

app.use(errorHandler);

export default app;
