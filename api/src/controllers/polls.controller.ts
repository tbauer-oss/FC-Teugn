import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { accessibleTeamIds, ownPlayerIds } from '../services/team-access';
import { Permission } from '../security/permissions';
import { audit, DomainError, mutation, oneOf, permitted, requireTeam, stringIds, textValue } from '../services/talents-domain';
import { buildVotingUnits, validateVote } from '../services/poll-units';
import { enqueueNotice } from '../services/talents-notices';

async function pollContext(req: Request) {
  const poll = await prisma.teamPoll.findUnique({ where: { id: req.params.id }, include: { units: true } });
  if (!poll) throw new DomainError(404, 'Umfrage nicht gefunden.');
  const teamIds = await accessibleTeamIds(req.user!);
  const own = await ownPlayerIds(req.user!);
  const manage = permitted(req.user!, Permission.SEND_ANNOUNCEMENTS) && poll.teamIds.every(id => teamIds.includes(id));
  const units = poll.units.filter(unit => unit.authorizedUserIds.includes(req.user!.id) &&
    (poll.unitType === 'PERSON' ? poll.teamIds.some(id => teamIds.includes(id)) : unit.playerIds.some(id => own.includes(id))));
  if (!manage && !units.length) throw new DomainError(403, 'Kein Zugriff auf diese Umfrage.');
  return { poll, manage, units };
}
export async function listPolls(req: Request, res: Response) {
  const teams = await accessibleTeamIds(req.user!);
  const own = await ownPlayerIds(req.user!);
  const staff = permitted(req.user!, Permission.SEND_ANNOUNCEMENTS);
  const polls = await prisma.teamPoll.findMany({ where: { OR: [
    ...(staff ? [{ teamIds: { hasSome: teams } }] : []),
    { units: { some: { authorizedUserIds: { has: req.user!.id } } } },
  ] }, include: { units: true }, orderBy: { createdAt: 'desc' }, take: 100 });
  return res.json(polls.flatMap(poll => {
    const canManage = staff && poll.teamIds.every(id => teams.includes(id));
    const myUnits = poll.units.filter(u => u.authorizedUserIds.includes(req.user!.id) &&
      (poll.unitType === 'PERSON' ? poll.teamIds.some(id => teams.includes(id)) : u.playerIds.some(id => own.includes(id))));
    if (!canManage && !myUnits.length) return [];
    const closed = !!poll.closedAt || poll.endsAt <= new Date();
    const showResults = canManage || poll.resultsVisibility === 'ALWAYS' || closed;
    const { units, ...details } = poll;
    return [{ ...details, canManage, closed,
      totalUnits: units.length, responseCount: units.filter(u => u.respondedAt).length,
      results: showResults ? poll.options.map((_, i) => units.filter(u => u.choices.includes(i)).length) : null,
      myUnits: myUnits.map(({ id, label, choices, respondedAt }) => ({ id, label, choices, respondedAt })),
    }];
  }));
}
export async function createPoll(req: Request, res: Response) {
  const teamIds = stringIds(req.body.teamIds, 20);
  if (!teamIds.length) throw new DomainError(400, 'Mindestens eine Mannschaft auswählen.');
  for (const id of teamIds) await requireTeam(req.user!, id, Permission.SEND_ANNOUNCEMENTS);
  const question = textValue(req.body.question, 'Frage', 300);
  const options = stringIds(req.body.options, 10);
  if (options.length < 2) throw new DomainError(400, 'Mindestens zwei unterschiedliche Antworten angeben.');
  const unitType = oneOf(req.body.unitType, ['PERSON', 'FAMILY', 'CHILD']);
  const resultsVisibility = oneOf(req.body.resultsVisibility, ['ALWAYS', 'AFTER_CLOSE']);
  const endsAt = new Date(String(req.body.endsAt));
  if (!Number.isFinite(endsAt.getTime()) || endsAt <= new Date() || endsAt.getTime() > Date.now() + 366 * 86400000) throw new DomainError(400, 'Eine zukünftige Frist innerhalb eines Jahres auswählen.');
  return mutation(req, res, async tx => {
    const players = await tx.player.findMany({ where: { teamId: { in: teamIds }, status: 'ACTIVE' }, include: { parentLinks: true } });
    const users = await tx.user.findMany({ where: { status: 'APPROVED', OR: [
      { teamId: { in: teamIds } }, { memberships: { some: { teamId: { in: teamIds }, status: 'APPROVED' } } },
      { parentLinks: { some: { playerId: { in: players.map(p => p.id) } } } },
    ] }, select: { id: true, name: true } });
    const allowed = new Set(users.map(u => u.id));
    const units = buildVotingUnits(unitType, players.map(p => ({ id: p.id,
      name: p.preferredName || `${p.firstName} ${p.lastName}`,
      userIds: [...p.parentLinks.map(l => l.parentId), ...(p.userId ? [p.userId] : [])].filter(id => allowed.has(id)),
    })), users);
    if (!units.length) throw new DomainError(400, 'Für diese Auswahl sind noch keine Teilnehmer vorhanden.');
    const poll = await tx.teamPoll.create({ data: { authorId: req.user!.id, teamIds,
      question, options, unitType, resultsVisibility, multiple: req.body.multiple === true, endsAt,
      units: { create: units } } });
    await enqueueNotice(tx, units.flatMap(u => u.authorizedUserIds), 'Neue Umfrage', question, '/talents/polls', poll.id);
    await audit(tx, req.user!, teamIds[0], 'POLL_CREATED', poll.id);
    return poll;
  });
}
export async function votePoll(req: Request, res: Response) {
  const context = await pollContext(req);
  const unit = context.units.find(u => u.id === req.body.unitId);
  if (!unit) throw new DomainError(403, 'Keine Berechtigung für diese Stimme.');
  let choices: number[];
  try { choices = validateVote(req.body.choices, context.poll.options.length, context.poll.multiple); }
  catch (error) { throw new DomainError(400, (error as Error).message); }
  return mutation(req, res, async tx => {
    const poll = await tx.teamPoll.findUniqueOrThrow({ where: { id: context.poll.id } });
    if (poll.closedAt || poll.archivedAt || poll.endsAt <= new Date()) throw new DomainError(409, 'Die Abstimmung ist bereits beendet.');
    const result = await tx.pollUnit.update({ where: { id: unit.id }, data: { choices, respondedById: req.user!.id, respondedAt: new Date() } });
    return { id: result.id, choices: result.choices, respondedAt: result.respondedAt };
  });
}
export async function managePoll(req: Request, res: Response) {
  const { poll, manage } = await pollContext(req);
  if (!manage) throw new DomainError(403, 'Nur das zuständige Trainerteam kann diese Umfrage verwalten.');
  const action = oneOf(req.body.action, ['CLOSE', 'ARCHIVE', 'REMIND']);
  return mutation(req, res, async tx => {
    const current = await tx.teamPoll.findUniqueOrThrow({ where: { id: poll.id }, include: { units: true } });
    if (action === 'REMIND') {
      if (current.closedAt || current.archivedAt || current.endsAt <= new Date()) throw new DomainError(409, 'Die Umfrage ist beendet.');
      const pending = current.units.filter(u => !u.respondedAt);
      await enqueueNotice(tx, pending.flatMap(u => u.authorizedUserIds), 'Rückmeldung zur Umfrage offen', current.question, '/talents/polls', poll.id);
      return { pendingUnits: pending.length };
    }
    const updated = await tx.teamPoll.update({ where: { id: poll.id }, data: action === 'CLOSE' ? { closedAt: new Date() } : { closedAt: current.closedAt ?? new Date(), archivedAt: new Date() } });
    await audit(tx, req.user!, poll.teamIds[0], `POLL_${action}`, poll.id);
    return updated;
  });
}
