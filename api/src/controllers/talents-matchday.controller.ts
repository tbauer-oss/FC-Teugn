import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { DomainError, requireTeam, textValue, mutation, permitted } from '../services/talents-domain';
import { Permission } from '../security/permissions';
import { talentsReport } from '../services/talents-report';

export async function printReport(req: Request, res: Response) {
  const title = textValue(req.body.title, 'Titel', 100), content = textValue(req.body.content, 'Inhalt', 30000);
  res.set({ 'Content-Type': 'application/pdf', 'Content-Disposition': 'attachment; filename="FC-Teugn-Bericht.pdf"', 'Cache-Control': 'no-store' });
  return res.send(await talentsReport(title, content));
}
export async function matchdayReadiness(req: Request, res: Response) {
  const event = await prisma.event.findUnique({ where: { id: req.params.id }, include: {
    matchDetails: true, carpoolNeeds: true, carpoolOffers: { include: { passengers: true } }, kitLaundryDuty: { include: { assignedPlayer: true } },
    participants: true, attendance: true, squads: { include: { members: { include: { player: true } }, lineup: true } }, playerMatchStats: true,
  } });
  if (!event || event.type !== 'MATCH') throw new DomainError(404, 'Spiel nicht gefunden.');
  await requireTeam(req.user!, event.teamId, Permission.NOMINATE_SQUAD);
  const candidates = event.participants.filter(p => p.playerId && p.responseRequired).map(p => p.playerId!);
  const players = candidates.length ? candidates : (await prisma.player.findMany({ where: { teamId: event.teamId, status: 'ACTIVE' }, select: { id: true } })).map(p => p.id);
  const missing = players.filter(id => {
    const reply = event.attendance.find(a => a.playerId === id);
    return !reply || ['UNKNOWN', 'MAYBE'].includes(reply.status) || (!reply.absenceId && event.responseRevisionAt && (!reply.respondedAt || reply.respondedAt < event.responseRevisionAt));
  }).length;
  const openRides = event.carpoolNeeds.filter(n => n.status === 'OPEN').length + event.carpoolOffers.reduce((n, o) => n + o.passengers.filter(p => p.status === 'REQUESTED').length, 0);
  const dayStart = new Date(event.startAt); dayStart.setUTCHours(0, 0, 0, 0);
  const checklists = await prisma.checklistRun.findMany({ where: { teamId: event.teamId, OR: [{ eventId: event.id }, { eventId: null, status: 'ACTIVE', dueAt: { gte: dayStart, lt: new Date(dayStart.getTime() + 86400000) } }] }, include: { items: true } });
  const checks = [
    { title: 'Rückmeldungen', detail: missing ? `${missing} Antworten offen oder erneut zu bestätigen` : 'Alle Antworten geklärt', ready: missing === 0, route: `/events/${event.id}` },
    { title: 'Fahrgemeinschaften', detail: openRides ? `${openRides} Mitfahrvorgänge ungeklärt` : 'Keine offenen Mitfahrvorgänge', ready: openRides === 0, route: `/events/${event.id}` },
    { title: 'Trikotdienst', detail: event.kitLaundryDuty?.assignedPlayer ? `${event.kitLaundryDuty.assignedPlayer.firstName} ${event.kitLaundryDuty.assignedPlayer.lastName}` : 'Noch nicht besetzt', ready: ['CONFIRMED', 'COMPLETED'].includes(event.kitLaundryDuty?.status ?? ''), route: `/matches/${event.id}?tab=overview` },
    ...checklists.map(c => ({ title: c.title, detail: `${c.items.filter(i => i.isCompleted).length} von ${c.items.length} erledigt`, ready: c.items.every(i => !i.isRequired || i.isCompleted), route: `/operations?teamId=${event.teamId}` })),
  ];
  const squad = event.squads[0];
  const nominated = squad?.members.filter(m => ['NOMINATED', 'RESERVE'].includes(m.status)) ?? [];
  const formatter = new Intl.DateTimeFormat('de-DE', { timeZone: 'Europe/Berlin', dateStyle: 'medium', timeStyle: 'short' });
  const minutes = nominated.map(m => ({ playerId: m.playerId, name: `${m.player.firstName} ${m.player.lastName}`, planned: m.plannedMinutes,
    actual: event.playerMatchStats.find(s => s.playerId === m.playerId)?.minutesPlayed ?? null }));
  const briefing = [event.title, `Anstoß: ${formatter.format(event.startAt)}`, `Spielort: ${event.location}${event.address ? ', ' + event.address : ''}`,
    `Treffpunkt: ${event.meetingLocation ?? 'Noch festlegen'}${event.meetingAt ? ' · ' + formatter.format(event.meetingAt) : ''}`,
    `Ausrüstung: ${event.equipment ?? 'Siehe Trainerhinweise'}`, `Kleidung: ${event.clothing ?? 'Siehe Trainerhinweise'}`, '',
    `Kader (${squad?.publishedAt ? 'veröffentlicht' : 'Trainerentwurf'}):`, ...minutes.map(m => `${m.name} · geplant ${m.planned ?? 'offen'} Min. · tatsächlich ${m.actual ?? 'noch nicht erfasst'}${m.actual == null ? '' : ' Min.'}`), '',
    'Organisation:', ...checks.map(c => `${c.ready ? 'Erledigt' : 'Offen'}: ${c.title} – ${c.detail}`), '',
    event.matchDetails?.bfvUrl ? `Kalenderquelle: ${event.matchDetails.bfvUrl}` : 'Terminangaben: manuell gepflegt',
    'Kader, Treffpunkt und Dienste: vereinsintern gepflegt.', 'Offizieller Spielbericht: im SpielPLUS-System prüfen und bearbeiten.',
  ].join('\n');
  return res.json({ eventId: event.id, teamId: event.teamId, checks, minutes, briefing, sourceUrl: event.matchDetails?.bfvUrl,
    canCreateChecklist: permitted(req.user!, Permission.MANAGE_TEAM_OPERATIONS) && !checklists.some(c => c.eventId === event.id) });
}

export async function createMatchdayChecklist(req: Request, res: Response) {
  const event = await prisma.event.findUnique({ where: { id: req.params.id } });
  if (!event || event.type !== 'MATCH') throw new DomainError(404, 'Spiel nicht gefunden.');
  await requireTeam(req.user!, event.teamId, Permission.MANAGE_TEAM_OPERATIONS);
  const tournament = ['TOURNAMENT', 'INDOOR_TOURNAMENT', 'FOOTBALL_FESTIVAL'].includes(event.category);
  const title = tournament ? 'Turnier' : event.homeAway === 'AWAY' ? 'Auswärtsspiel' : 'Heimspiel';
  const items = ['Kader und Rückmeldungen geprüft', 'Treffpunkt und Ausrüstung bekannt', 'Trikotdienst bestätigt',
    ...(tournament ? ['Spielplan und Veranstalterlink geprüft', 'Verpflegung und Pausen geplant'] : event.homeAway === 'AWAY' ? ['Mitfahrten und Abfahrt bestätigt', 'Adresse und Anfahrt geprüft'] : ['Platz, Tore und Kabinen vorbereitet', 'Gastmannschaft informiert']),
    'SpielPLUS-Angaben manuell geprüft'];
  return mutation(req, res, async tx => {
    const existing = await tx.checklistRun.findUnique({ where: { eventId: event.id } });
    if (existing) return existing;
    const template = await tx.checklistTemplate.findFirst({ where: { teamId: event.teamId, title: `Spieltagsvorlage: ${title}`, isArchived: false }, include: { items: { orderBy: { position: 'asc' } } } }) ??
      await tx.checklistTemplate.create({ data: { teamId: event.teamId, title: `Spieltagsvorlage: ${title}`, category: 'SPIELTAG', createdById: req.user!.id,
        items: { create: items.map((title, position) => ({ title, position, isRequired: true })) } }, include: { items: true } });
    return tx.checklistRun.create({ data: { teamId: event.teamId, eventId: event.id, templateId: template.id, title: `${title}: ${event.title}`,
      category: 'SPIELTAG', dueAt: event.meetingAt ?? event.startAt, createdById: req.user!.id,
      items: { create: template.items.map(i => ({ title: i.title, position: i.position, isRequired: i.isRequired })) } } });
  });
}
