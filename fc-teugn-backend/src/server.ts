import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import authRoutes from './routes/auth.routes';
import matchesRoutes from './routes/matches.routes';
import playersRoutes from './routes/players.routes';
import trainingsRoutes from './routes/trainings.routes';
import eventsRoutes from './routes/events.routes';
import leagueRoutes from './routes/league.routes';
import { errorHandler } from './middleware/errorHandler';
import usersRoutes from './routes/users.routes';

dotenv.config();

const app = express();

app.use(cors());
app.use(express.json());

app.get('/', (_req, res) => res.json({ status: 'ok' }));

app.use('/auth', authRoutes);
app.use('/matches', matchesRoutes);
app.use('/players', playersRoutes);
app.use('/trainings', trainingsRoutes);
app.use('/events', eventsRoutes);
app.use('/league', leagueRoutes);
app.use('/users', usersRoutes);

app.use(errorHandler);

export default app;
