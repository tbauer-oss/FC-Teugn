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
  opponentId: string | null;
  opponentClubName: string;
  opponentTeamDesignation: string | null;
  isHome: boolean;
  competition: string | null;
  division: string | null;
  matchDay: string | null;
  status: string;
  ourGoals: number | null;
  theirGoals: number | null;
  periodCount: number | null;
  periodMinutes: number | null;
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

function explicitMatchTiming(
  countValue: string,
  minutesValue: string,
  description = '',
) {
  let periodCount = integer(countValue);
  let periodMinutes = integer(minutesValue);
  if (periodCount == null && periodMinutes == null) {
    const described = description.match(
      /\b([1-8])\s*[x×]\s*(\d{1,2})\s*(?:min(?:\.|uten?)?)?\b/i,
    );
    if (described) {
      periodCount = Number(described[1]);
      periodMinutes = Number(described[2]);
    }
  }
  if (
    periodCount == null ||
    periodMinutes == null ||
    periodCount < 1 ||
    periodCount > 8 ||
    periodMinutes < 1 ||
    periodMinutes > 90 ||
    periodCount * periodMinutes > 180
  ) {
    return null;
  }
  return { periodCount, periodMinutes };
}

export type CompetitionTeamIdentity = {
  rawName: string;
  clubName: string;
  teamDesignation: string | null;
  displayName: string;
};

export type CompetitionSourceOptions = {
  ownTeamNames?: string[];
  displayOwnTeamName?: string;
};

function withoutPlayingCommunityPrefix(input: string) {
  return input
    .replace(/^\s*\(\s*SG\s*\)\s*/i, '')
    .replace(/^\s*SG\s+/i, '')
    .trim();
}

/**
 * Converts BfV team labels such as `FC Hausen E7 2` into the app's stable
 * youth-team notation (`FC Hausen E2`). The number directly behind the youth
 * letter is the playing format in BfV exports; a following number is the
 * actual squad number.
 */
export function competitionTeamIdentity(input: string): CompetitionTeamIdentity {
  const rawName = unescapeIcs(input).trim();
  const cleaned = withoutPlayingCommunityPrefix(rawName);
  const match = cleaned.match(
    /^(.*?)(?:\s+)([A-G])(?:\s*(\d{1,2}))?(?:\s*-?\s*Jun\.?\s*)?(?:\s+(\d{1,2}))?$/i,
  );
  if (!match) {
    return {
      rawName,
      clubName: cleaned,
      teamDesignation: null,
      displayName: cleaned,
    };
  }
  const [, rawClub, rawLetter, firstNumber, explicitSquad] = match;
  const clubName = withoutPlayingCommunityPrefix(rawClub);
  const letter = rawLetter.toLocaleUpperCase('de-DE');
  const formatNumbers = new Set(['3', '5', '7', '9', '11']);
  const squadNumber = explicitSquad ||
    (firstNumber && !formatNumbers.has(firstNumber) ? firstNumber : '1');
  const teamDesignation = `${letter}${squadNumber}`;
  return {
    rawName,
    clubName,
    teamDesignation,
    displayName: `${clubName} ${teamDesignation}`.trim(),
  };
}

function normalizedClubIdentity(input: string) {
  return competitionTeamIdentity(input).clubName
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLocaleLowerCase('de-DE')
    .replace(/[^a-z0-9]/g, '');
}

function escapeRegExp(input: string) {
  return input.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function ownTeamPattern(input: string) {
  const clubName = competitionTeamIdentity(input).clubName;
  if (!clubName) return null;
  const flexibleClubName = escapeRegExp(clubName)
    .replace(/\\ /g, '\\s+')
    .replace(/\\\//g, '\\s*\/\\s*');
  return new RegExp(
    `(?:\\(\\s*SG\\s*\\)\\s*|SG\\s+)?${flexibleClubName}` +
      '(?:\\s+[A-G](?:\\s*\\d{1,2})?(?:\\s*-?\\s*Jun\\.?)?(?:\\s+\\d{1,2})?)?',
    'i',
  );
}

function pairingFromSummary(
  summary: string,
  options: CompetitionSourceOptions = {},
) {
  const [pairing = '', ...metadata] = summary
    .split(/\s*,\s*/)
    .map((part) => part.trim())
    .filter(Boolean);
  const ownNames = options.ownTeamNames?.length
    ? options.ownTeamNames
    : ['FC Teugn'];
  const ownIdentities = new Set(
    ownNames.map(normalizedClubIdentity).filter(Boolean),
  );
  for (const ownName of ownNames) {
    const pattern = ownTeamPattern(ownName);
    const ownTeam = pattern ? pairing.match(pattern) : null;
    if (ownTeam?.index == null) continue;
    const before = pairing.slice(0, ownTeam.index).replace(/\s*[-–—]\s*$/, '');
    const after = pairing
      .slice(ownTeam.index + ownTeam[0].length)
      .replace(/^\s*[-–—]\s*/, '');
    const isHome = ownTeam.index === 0;
    const opponentRaw = (isHome ? after : before).trim();
    if (!opponentRaw) continue;
    return {
      isHome,
      ownTeam: competitionTeamIdentity(ownTeam[0]),
      opponent: competitionTeamIdentity(opponentRaw),
      competition: metadata[0] || null,
      division: metadata.slice(1).join(', ') || null,
    };
  }
  const teams = pairing
    .split(/\s+(?:[-–—]|vs\.?|gegen)\s+/i)
    .map((item) => item.trim())
    .filter(Boolean);
  if (teams.length === 2) {
    const homeMatches = ownIdentities.has(normalizedClubIdentity(teams[0]));
    const awayMatches = ownIdentities.has(normalizedClubIdentity(teams[1]));
    if (homeMatches === awayMatches) return null;
    const isHome = homeMatches;
    return {
      isHome,
      ownTeam: competitionTeamIdentity(isHome ? teams[0] : teams[1]),
      opponent: competitionTeamIdentity(isHome ? teams[1] : teams[0]),
      competition: metadata[0] || null,
      division: metadata.slice(1).join(', ') || null,
    };
  }
  return null;
}

function locationParts(value: string) {
  const location = value.trim();
  if (!location) return { location: 'Noch offen', address: null };
  const parts = location.split(/\s*,\s*/).filter(Boolean);
  const postalIndex = parts.findIndex((part) => /\b\d{5}\b/.test(part));
  if (postalIndex > 0) {
    const addressStart = Math.max(1, postalIndex - 1);
    return {
      location: parts.slice(0, addressStart).join(', ') || parts[0],
      address: parts.slice(addressStart).join(', '),
    };
  }
  return { location, address: null };
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
    const opponentIdentity = competitionTeamIdentity(opponent);
    const rawPeriodCount = value(
      row,
      'periodcount',
      'abschnitte',
      'spielabschnitte',
      'halbzeiten',
    );
    const rawPeriodMinutes = value(
      row,
      'periodminutes',
      'minutenproabschnitt',
      'minabschnitt',
      'spielzeitproabschnitt',
    );
    const timing = explicitMatchTiming(
      rawPeriodCount,
      rawPeriodMinutes,
      value(row, 'spielzeit', 'duration', 'dauer'),
    );
    if ((rawPeriodCount || rawPeriodMinutes) && !timing) {
      messages.push(
        'Die angegebene Spielzeit ist unvollständig oder ungültig und wird aus der Mannschaft übernommen.',
      );
    }
    const base = {
      title: value(row, 'title', 'titel') || `Spiel gegen ${opponentIdentity.displayName}`,
      startAt: start!.toISOString(),
      endAt: null,
      location,
      address: value(row, 'address', 'adresse') || null,
      opponent: opponentIdentity.displayName,
      opponentId: null,
      opponentClubName: opponentIdentity.clubName,
      opponentTeamDesignation: opponentIdentity.teamDesignation,
      isHome: boolean(value(row, 'ishome', 'heim', 'heimspiel'), true),
      competition: value(row, 'competition', 'wettbewerb', 'liga') || null,
      division: value(row, 'division', 'staffel') || null,
      matchDay: value(row, 'matchday', 'spieltag') || null,
      status: status(value(row, 'status', 'spielstatus')),
      ourGoals: integer(value(row, 'ourgoals', 'torefcteugn', 'toreheim')),
      theirGoals: integer(value(row, 'theirgoals', 'toregegner', 'toregast')),
      periodCount: timing?.periodCount ?? null,
      periodMinutes: timing?.periodMinutes ?? null,
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

function icsRows(
  content: string,
  options: CompetitionSourceOptions = {},
): ParsedCompetitionRow[] {
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
    const pairing = pairingFromSummary(summary, options);
    if (!pairing) {
      return {
        rowNumber: index + 1,
        match: null,
        messages: [
          ...messages,
          'Heim- und Auswärtsteam konnten aus SUMMARY nicht sicher erkannt werden.',
        ],
      };
    }
    const venue = locationParts(properties.get('LOCATION')?.trim() ?? '');
    const end = icsDate(
      properties.get('DTEND') ?? '',
      timeZones.get('DTEND'),
    );
    // DTSTART/DTEND beschreiben in BfV-Dateien häufig den gesamten Platz-Slot
    // inklusive Pausen. Nur eine ausdrücklich notierte Abschnittszeit gilt
    // deshalb als Spielzeit; andernfalls übernimmt der Import die Mannschaft.
    const timing = explicitMatchTiming(
      properties.get('X-PERIOD-COUNT') ?? '',
      properties.get('X-PERIOD-MINUTES') ?? '',
      [
        properties.get('DESCRIPTION'),
        properties.get('X-GAME-DURATION'),
        properties.get('X-SPIELZEIT'),
      ].filter(Boolean).join(' '),
    );
    const base = {
      title: pairing.isHome
        ? `${options.displayOwnTeamName ?? 'FC Teugn'} – ${pairing.opponent.displayName}`
        : `${pairing.opponent.displayName} – ${options.displayOwnTeamName ?? 'FC Teugn'}`,
      startAt: start!.toISOString(),
      endAt: end?.toISOString() ?? null,
      location: venue.location,
      address: venue.address,
      opponent: pairing.opponent.displayName,
      opponentId: null,
      opponentClubName: pairing.opponent.clubName,
      opponentTeamDesignation: pairing.opponent.teamDesignation,
      isHome: pairing.isHome,
      competition:
        pairing.competition ||
        properties.get('CATEGORIES')?.trim() ||
        'BfV-Spielplan',
      division: pairing.division,
      matchDay: null,
      status:
        properties.get('STATUS')?.toUpperCase() === 'CANCELLED' ||
        /abgesagt|abgesetzt|entfällt/i.test(summary)
          ? 'CANCELLED'
          : 'PLANNED',
      ourGoals: null,
      theirGoals: null,
      periodCount: timing?.periodCount ?? null,
      periodMinutes: timing?.periodMinutes ?? null,
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
  options: CompetitionSourceOptions = {},
) {
  return format === 'ICS' ? icsRows(content, options) : csvRows(content);
}

export function competitionMatchChecksum(match: NormalizedCompetitionMatch) {
  return crypto
    .createHash('sha256')
    .update(JSON.stringify(match))
    .digest('hex');
}
