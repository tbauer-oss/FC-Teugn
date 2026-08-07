import crypto from 'node:crypto';
import { parse } from 'csv-parse/sync';

export type CompetitionImportFormat = 'CSV' | 'ICS';

export type NormalizedCompetitionMatch = {
  externalId: string;
  title: string;
  startAt: string;
  endAt: string | null;
  location: string;
  address: string | null;
  opponent: string;
  isHome: boolean;
  competition: string | null;
  division: string | null;
  matchDay: string | null;
  status: string;
  ourGoals: number | null;
  theirGoals: number | null;
  sourceUrl: string | null;
};

export type ParsedCompetitionRow = {
  rowNumber: number;
  match: NormalizedCompetitionMatch | null;
  messages: string[];
};

function value(
  row: Record<string, unknown>,
  ...keys: string[]
) {
  const normalized = new Map(
    Object.entries(row).map(([key, entry]) => [
      key.toLowerCase().replace(/[^a-z0-9äöüß]/g, ''),
      String(entry ?? '').trim(),
    ]),
  );
  for (const key of keys) {
    const found = normalized.get(
      key.toLowerCase().replace(/[^a-z0-9äöüß]/g, ''),
    );
    if (found) return found;
  }
  return '';
}

function dateTime(dateValue: string, timeValue = '') {
  const combined = `${dateValue.trim()} ${timeValue.trim()}`.trim();
  const german = combined.match(
    /^(\d{1,2})\.(\d{1,2})\.(\d{4})(?:\s+(\d{1,2}):(\d{2}))?$/,
  );
  if (german) {
    const [, day, month, year, hour = '0', minute = '0'] = german;
    const result = new Date(
      Number(year),
      Number(month) - 1,
      Number(day),
      Number(hour),
      Number(minute),
    );
    return Number.isNaN(result.getTime()) ? null : result;
  }
  const result = new Date(combined);
  return Number.isNaN(result.getTime()) ? null : result;
}

function integer(input: string) {
  if (!input.trim()) return null;
  const result = Number(input);
  return Number.isInteger(result) && result >= 0 ? result : null;
}

function boolean(input: string, fallback = true) {
  if (!input) return fallback;
  return ['1', 'true', 'ja', 'yes', 'heim', 'home'].includes(
    input.toLowerCase(),
  );
}

function status(input: string) {
  const normalized = input.toUpperCase().replace(/[^A-Z]/g, '_');
  const aliases: Record<string, string> = {
    GEPLANT: 'PLANNED',
    BESTAETIGT: 'CONFIRMED',
    BESTÄTIGT: 'CONFIRMED',
    VERSCHOBEN: 'POSTPONED',
    ABGESAGT: 'CANCELLED',
    BEENDET: 'FINISHED',
    NACHGETRAGEN: 'RECORDED',
  };
  return aliases[normalized] ?? (normalized || 'PLANNED');
}

function derivedExternalId(match: Omit<NormalizedCompetitionMatch, 'externalId'>) {
  return `derived:${crypto
    .createHash('sha256')
    .update(`${match.startAt}|${match.opponent}|${match.location}`)
    .digest('hex')
    .slice(0, 24)}`;
}

function csvRows(content: string): ParsedCompetitionRow[] {
  let records: Record<string, unknown>[];
  try {
    records = parse(content, {
      columns: true,
      bom: true,
      skip_empty_lines: true,
      trim: true,
      relax_column_count: true,
      delimiter: content.includes(';') ? ';' : ',',
    });
  } catch (error) {
    return [{
      rowNumber: 1,
      match: null,
      messages: [
        `CSV konnte nicht gelesen werden: ${
          error instanceof Error ? error.message : 'unbekannter Fehler'
        }`,
      ],
    }];
  }
  return records.slice(0, 1000).map((row, index) => {
    const messages: string[] = [];
    const start = dateTime(
      value(row, 'date', 'datum', 'spieldatum', 'startat'),
      value(row, 'time', 'uhrzeit', 'anstoß', 'anstoss'),
    );
    const opponent = value(row, 'opponent', 'gegner', 'gast', 'gastteam');
    if (!start) messages.push('Datum oder Uhrzeit ist ungültig.');
    if (!opponent) messages.push('Gegner fehlt.');
    if (messages.length) return { rowNumber: index + 2, match: null, messages };
    const location =
      value(row, 'location', 'ort', 'spielstätte', 'spielstaette') ||
      'Noch offen';
    const base = {
      title: value(row, 'title', 'titel') || `Spiel gegen ${opponent}`,
      startAt: start!.toISOString(),
      endAt: null,
      location,
      address: value(row, 'address', 'adresse') || null,
      opponent,
      isHome: boolean(value(row, 'ishome', 'heim', 'heimspiel'), true),
      competition: value(row, 'competition', 'wettbewerb', 'liga') || null,
      division: value(row, 'division', 'staffel') || null,
      matchDay: value(row, 'matchday', 'spieltag') || null,
      status: status(value(row, 'status', 'spielstatus')),
      ourGoals: integer(value(row, 'ourgoals', 'torefcteugn', 'toreheim')),
      theirGoals: integer(value(row, 'theirgoals', 'toregegner', 'toregast')),
      sourceUrl: value(row, 'bfvurl', 'sourceurl', 'quelle') || null,
    };
    const externalId =
      value(row, 'externalid', 'bfvmatchid', 'spielkennung', 'id') ||
      derivedExternalId(base);
    if (externalId.startsWith('derived:')) {
      messages.push('Keine externe Spielkennung; stabile Ersatzkennung erzeugt.');
    }
    return { rowNumber: index + 2, match: { externalId, ...base }, messages };
  });
}

function unescapeIcs(value: string) {
  return value
    .replace(/\\n/gi, '\n')
    .replace(/\\,/g, ',')
    .replace(/\\;/g, ';')
    .replace(/\\\\/g, '\\');
}

function zonedDate(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
  second: number,
  timeZone: string,
) {
  const guess = Date.UTC(year, month - 1, day, hour, minute, second);
  try {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hourCycle: 'h23',
    }).formatToParts(new Date(guess));
    const byType = new Map(parts.map((part) => [part.type, part.value]));
    const represented = Date.UTC(
      Number(byType.get('year')),
      Number(byType.get('month')) - 1,
      Number(byType.get('day')),
      Number(byType.get('hour')),
      Number(byType.get('minute')),
      Number(byType.get('second')),
    );
    return new Date(guess - (represented - guess));
  } catch {
    return new Date(guess);
  }
}

function icsDate(value: string, timeZone = 'Europe/Berlin') {
  const match = value.match(
    /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?)?(Z)?$/,
  );
  if (!match) return null;
  const [, year, month, day, hour = '0', minute = '0', second = '0', utc] =
    match;
  const result = utc
    ? new Date(
        Date.UTC(
          Number(year),
          Number(month) - 1,
          Number(day),
          Number(hour),
          Number(minute),
          Number(second),
        ),
      )
    : zonedDate(
        Number(year),
        Number(month),
        Number(day),
        Number(hour),
        Number(minute),
        Number(second),
        timeZone,
      );
  return Number.isNaN(result.getTime()) ? null : result;
}

function icsRows(content: string): ParsedCompetitionRow[] {
  const unfolded = content.replace(/\r?\n[ \t]/g, '');
  const events = unfolded.match(/BEGIN:VEVENT[\s\S]*?END:VEVENT/g) ?? [];
  if (!events.length) {
    return [{
      rowNumber: 1,
      match: null,
      messages: ['Keine VEVENT-Einträge in der ICS-Datei gefunden.'],
    }];
  }
  return events.slice(0, 1000).map((block, index) => {
    const properties = new Map<string, string>();
    const timeZones = new Map<string, string>();
    for (const line of block.split(/\r?\n/)) {
      const separator = line.indexOf(':');
      if (separator < 0) continue;
      const keyPart = line.slice(0, separator);
      const key = keyPart.split(';')[0].toUpperCase();
      properties.set(key, unescapeIcs(line.slice(separator + 1)));
      const zone = keyPart.match(/(?:^|;)TZID=([^;:]+)/i)?.[1];
      if (zone) timeZones.set(key, zone);
    }
    const messages: string[] = [];
    const start = icsDate(
      properties.get('DTSTART') ?? '',
      timeZones.get('DTSTART'),
    );
    const summary = properties.get('SUMMARY')?.trim() ?? '';
    if (!start) messages.push('DTSTART fehlt oder ist ungültig.');
    if (!summary) messages.push('SUMMARY fehlt.');
    if (messages.length) return { rowNumber: index + 1, match: null, messages };
    const parts = summary.split(/\s+(?:-|–|:|vs\.?|gegen)\s+/i);
    const isHome = /^fc\s+teugn/i.test(parts[0] ?? '');
    const opponent = (
      isHome ? parts[1] : parts.find((part) => !/^fc\s+teugn/i.test(part))
    )?.trim() || summary;
    const location = properties.get('LOCATION')?.trim() || 'Noch offen';
    const end = icsDate(
      properties.get('DTEND') ?? '',
      timeZones.get('DTEND'),
    );
    const base = {
      title: summary,
      startAt: start!.toISOString(),
      endAt: end?.toISOString() ?? null,
      location,
      address: location === 'Noch offen' ? null : location,
      opponent,
      isHome,
      competition:
        properties.get('CATEGORIES')?.trim() ||
        properties.get('X-WR-CALNAME')?.trim() ||
        'BfV-Spielplan',
      division: null,
      matchDay: null,
      status:
        properties.get('STATUS')?.toUpperCase() === 'CANCELLED' ||
        /abgesagt|abgesetzt|entfällt/i.test(summary)
          ? 'CANCELLED'
          : 'PLANNED',
      ourGoals: null,
      theirGoals: null,
      sourceUrl: properties.get('URL')?.trim() || null,
    };
    const externalId =
      properties.get('UID')?.trim() || derivedExternalId(base);
    if (!properties.get('UID')) {
      messages.push('Keine UID; stabile Ersatzkennung erzeugt.');
    }
    return { rowNumber: index + 1, match: { externalId, ...base }, messages };
  });
}

export function parseCompetitionSource(
  format: CompetitionImportFormat,
  content: string,
) {
  return format === 'ICS' ? icsRows(content) : csvRows(content);
}

export function competitionMatchChecksum(match: NormalizedCompetitionMatch) {
  return crypto
    .createHash('sha256')
    .update(JSON.stringify(match))
    .digest('hex');
}
