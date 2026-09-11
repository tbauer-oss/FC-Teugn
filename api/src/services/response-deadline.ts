import { Prisma } from '@prisma/client';
import { DomainError } from './talents-domain';

const formatter = new Intl.DateTimeFormat('de-DE', {
  timeZone: 'Europe/Berlin', dateStyle: 'medium', timeStyle: 'short',
});

export function responseDeadlinePassed(deadline: Date | null | undefined, now = new Date()) {
  return Boolean(deadline && deadline.getTime() <= now.getTime());
}

export function responseDeadlineMessage(deadline: Date | null | undefined, now = new Date()) {
  if (!deadline) return '';
  return `${responseDeadlinePassed(deadline, now) ? 'Kader geschlossen seit' : 'Kader schließt am'} ${formatter.format(deadline)} Uhr (Ortszeit Deutschland). Danach sind Zu- und Absagen nur noch durch das Trainerteam möglich. Spätere Rückmeldungen werden nicht automatisch berücksichtigt; bitte das Trainerteam kontaktieren.`;
}

export function shiftedResponseDeadline(deadline: Date | null, oldStart: Date, newStart: Date) {
  return deadline ? new Date(deadline.getTime() + newStart.getTime() - oldStart.getTime()) : null;
}

/** Omitted fields preserve the existing lead time; explicit null removes the lock. */
export function responseDeadlineForWrite(
  body: Record<string, unknown>, startAt: Date,
  existing?: { startAt: Date; responseDeadline: Date | null; parentTournamentId?: string | null },
) {
  if (!Object.prototype.hasOwnProperty.call(body, 'responseDeadline')) {
    return existing ? shiftedResponseDeadline(existing.responseDeadline, existing.startAt, startAt) : null;
  }
  if (existing?.parentTournamentId) {
    if (body.responseDeadline === null) return existing.responseDeadline;
    throw new DomainError(409, 'Die Rückmeldefrist wird am gesamten Turnier festgelegt, nicht je Turnierpartie.');
  }
  if (body.responseDeadline === null) return null;
  const deadline = typeof body.responseDeadline === 'string' ? new Date(body.responseDeadline) : null;
  if (!deadline || !Number.isFinite(deadline.getTime()) || deadline >= startAt) {
    throw new DomainError(400, 'Bitte eine gültige Rückmeldefrist vor dem Spielbeginn wählen.');
  }
  return deadline;
}

/** Durable outbox: notify already informed families when the deadline changes. */
export async function recordResponseDeadlineChange(
  tx: Prisma.TransactionClient,
  event: { id: string; responseDeadline: Date | null; familyReleasedAt: Date | null },
  deadline: Date | null,
) {
  if (!event.familyReleasedAt || event.responseDeadline?.getTime() === deadline?.getTime()) return;
  await tx.eventChange.create({ data: {
    eventId: event.id,
    before: { responseDeadline: event.responseDeadline?.toISOString() ?? null },
    after: { responseDeadline: deadline?.toISOString() ?? null },
    fields: ['responseDeadline'],
  } });
}
