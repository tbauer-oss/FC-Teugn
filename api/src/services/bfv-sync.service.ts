import { prisma } from '../lib/prisma';
import {
  competitionMatchChecksum,
  parseCompetitionSource,
} from './competition-provider';
import { writeCompetitionMatch } from './competition-import-write.service';

const PROVIDER = 'BFV_ICS';
const MAX_ICS_BYTES = 2_000_000;

export function validatedBfvIcalUrl(value: string) {
  const url = new URL(value);
  if (
    url.protocol !== 'https:' ||
    url.hostname.toLowerCase() !== 'service.bfv.de' ||
    url.username ||
    url.password ||
    (url.port && url.port !== '443')
  ) {
    throw new Error('Die iCal-Adresse muss direkt vom offiziellen BfV-Dienst service.bfv.de stammen.');
  }
  return url;
}

export function validatedBfvViewUrl(value: string) {
  const url = new URL(value);
  const hostname = url.hostname.toLowerCase();
  if (
    url.protocol !== 'https:' ||
    !(hostname === 'bfv.de' || hostname.endsWith('.bfv.de')) ||
    url.username ||
    url.password ||
    (url.port && url.port !== '443')
  ) {
    throw new Error('Die BfV-Ansicht muss auf einer offiziellen bfv.de-Adresse liegen.');
  }
  return url;
}

async function fetchOfficialIcs(initialUrl: URL) {
  let url = initialUrl;
  for (let redirects = 0; redirects < 4; redirects += 1) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10_000);
    try {
      const response = await fetch(url, {
        signal: controller.signal,
        redirect: 'manual',
        headers: { accept: 'text/calendar, text/plain;q=0.9' },
      });
      if (response.status >= 300 && response.status < 400) {
        const location = response.headers.get('location');
        if (!location) throw new Error('BfV-Weiterleitung ohne Zieladresse.');
        url = validatedBfvIcalUrl(new URL(location, url).toString());
        continue;
      }
      if (!response.ok) {
        throw new Error(`Der BfV-Kalender antwortet mit Status ${response.status}.`);
      }
      const declaredLength = Number(response.headers.get('content-length') ?? 0);
      if (declaredLength > MAX_ICS_BYTES) {
        throw new Error('Der BfV-Kalender ist unerwartet groß.');
      }
      const content = await response.text();
      if (Buffer.byteLength(content, 'utf8') > MAX_ICS_BYTES) {
        throw new Error('Der BfV-Kalender ist unerwartet groß.');
      }
      return content;
    } finally {
      clearTimeout(timeout);
    }
  }
  throw new Error('Zu viele Weiterleitungen beim BfV-Kalender.');
}

export async function runBfvTeamSync(teamId: string) {
  const config = await prisma.bfvTeamSync.findUnique({ where: { teamId } });
  if (!config?.icalUrl) {
    throw new Error('Für diese Mannschaft ist noch keine BfV-iCal-Adresse hinterlegt.');
  }
  await prisma.bfvTeamSync.update({
    where: { teamId },
    data: { lastAttemptAt: new Date(), lastStatus: 'RUNNING', lastMessage: null },
  });
  try {
    const content = await fetchOfficialIcs(validatedBfvIcalUrl(config.icalUrl));
    const parsed = parseCompetitionSource('ICS', content).slice(0, 500);
    const matches = parsed.flatMap((row) => row.match ? [row.match] : []);
    const externalIds = [...new Set(matches.map((match) => match.externalId))];
    const references = await prisma.externalReference.findMany({
      where: { provider: PROVIDER, entityType: 'Event', externalId: { in: externalIds } },
    });
    const referenceById = new Map(references.map((item) => [item.externalId, item]));
    const events = await prisma.event.findMany({
      where: { id: { in: references.map((item) => item.entityId) } },
      select: { id: true, teamId: true, updatedAt: true, matchDetails: { select: { updatedAt: true } } },
    });
    const eventById = new Map(events.map((item) => [item.id, item]));
    let created = 0;
    let updated = 0;
    let skipped = 0;
    let conflicts = parsed.length - matches.length;

    for (const match of matches) {
      const reference = referenceById.get(match.externalId);
      if (!reference) {
        await prisma.$transaction((tx) =>
          writeCompetitionMatch(tx, teamId, PROVIDER, match),
        );
        created += 1;
        continue;
      }
      const event = eventById.get(reference.entityId);
      if (!event || event.teamId !== teamId) {
        conflicts += 1;
        continue;
      }
      if (reference.sourceChecksum === competitionMatchChecksum(match)) {
        skipped += 1;
        continue;
      }
      const locallyChanged = Math.max(
        event.updatedAt.getTime(),
        event.matchDetails?.updatedAt.getTime() ?? 0,
      ) > reference.lastSyncedAt.getTime() + 1000;
      if (locallyChanged) {
        conflicts += 1;
        continue;
      }
      await prisma.$transaction((tx) =>
        writeCompetitionMatch(tx, teamId, PROVIDER, match, event.id),
      );
      updated += 1;
    }

    const lastMessage = conflicts > 0
      ? `${conflicts} lokale oder ungültige Einträge wurden sicher ausgelassen.`
      : 'BfV-Spielplan ist aktuell.';
    return prisma.bfvTeamSync.update({
      where: { teamId },
      data: {
        lastSuccessAt: new Date(),
        lastStatus: conflicts > 0 ? 'SUCCESS_WITH_CONFLICTS' : 'SUCCESS',
        lastMessage,
        lastCreatedCount: created,
        lastUpdatedCount: updated,
        lastSkippedCount: skipped,
        lastConflictCount: conflicts,
      },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'BfV-Abgleich fehlgeschlagen.';
    await prisma.bfvTeamSync.update({
      where: { teamId },
      data: { lastStatus: 'ERROR', lastMessage: message.slice(0, 500) },
    });
    throw error;
  }
}

export async function processDueBfvSyncs(now = new Date(), limit = 3) {
  const dueBefore = new Date(now.getTime() - 15 * 60_000);
  const candidates = await prisma.bfvTeamSync.findMany({
    where: {
      enabled: true,
      icalUrl: { not: null },
      team: { deletedAt: null, isActive: true },
      OR: [{ lastAttemptAt: null }, { lastAttemptAt: { lte: dueBefore } }],
    },
    orderBy: { lastAttemptAt: { sort: 'asc', nulls: 'first' } },
    take: Math.max(1, Math.min(limit, 5)),
  });
  const results = [];
  for (const config of candidates) {
    const minimumAge = config.syncIntervalMinutes * 60_000;
    if (config.lastAttemptAt && now.getTime() - config.lastAttemptAt.getTime() < minimumAge) {
      continue;
    }
    try {
      const result = await runBfvTeamSync(config.teamId);
      results.push({ teamId: config.teamId, status: result.lastStatus });
    } catch (error) {
      results.push({
        teamId: config.teamId,
        status: 'ERROR',
        message: error instanceof Error ? error.message : 'Unbekannter Fehler',
      });
    }
  }
  return results;
}
