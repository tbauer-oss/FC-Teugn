import { Request, Response } from 'express';
import {
  ConsentStatus,
  ConsentType,
  DominantFoot,
  MatchStatus,
  PlayerGender,
  PlayerStatus,
  Prisma,
  TickerEventType,
} from '@prisma/client';
import { prisma } from '../lib/prisma';
import { Role } from '../types/enums';
import { hasPermission, Permission } from '../security/permissions';
import {
  accessibleTeamIds,
  contextualTeamIds,
  clubIdForTeam,
  TeamScopedUser,
  youthPlayerPoolTeamIds,
} from '../services/team-access';
import { mediaAssetUrl } from '../services/media-access';
import {
  ConsentSnapshot,
  hasActiveConsent,
  medicalProfileForConsent,
} from '../services/consent-policy';

const statisticGoalTypes: TickerEventType[] = [
  TickerEventType.HOME_GOAL,
  TickerEventType.AWAY_GOAL,
];

const publicPlayerSelect = {
  id: true,
  clubId: true,
  teamId: true,
  firstName: true,
  lastName: true,
  preferredName: true,
  birthDate: true,
  nationality: true,
  gender: true,
  position: true,
  secondaryPosition: true,
  dominantFoot: true,
  shirtNumber: true,
  passNumber: true,
  status: true,
  joinedAt: true,
  createdAt: true,
  updatedAt: true,
  photoAsset: {
    select: { id: true, deletedAt: true },
  },
  photoUrl: true,
  consents: {
    where: {
      type: {
        in: [ConsentType.PHOTO, ConsentType.MEDICAL_DATA] as ConsentType[],
      },
    },
    select: {
      type: true,
      status: true,
      expiresAt: true,
      evidence: {
        where: { action: ConsentStatus.GRANTED },
        orderBy: { createdAt: 'desc' as const },
        take: 1,
        select: { action: true, statement: true, createdAt: true },
      },
    },
  },
  team: {
    select: {
      id: true,
      name: true,
      shortName: true,
      teamNumber: true,
      ageGroup: { select: { id: true, name: true, code: true } },
    },
  },
  matchStatistics: {
    select: {
      goals: true,
      assists: true,
      appeared: true,
      started: true,
      minutesPlayed: true,
      isGoalkeeper: true,
      event: {
        select: {
          matchDetails: {
            select: { status: true, theirGoals: true },
          },
          teamMatchStatistic: {
            select: { theirGoals: true },
          },
          team: {
            select: {
              ageGroup: {
                select: {
                  season: {
                    select: { id: true, name: true, startDate: true },
                  },
                },
              },
            },
          },
        },
      },
    },
  },
  tickerGoals: {
    where: {
      revokedAt: null,
      type: { in: statisticGoalTypes },
    },
    select: {
      id: true,
      ticker: {
        select: {
          event: {
            select: {
              team: {
                select: {
                  ageGroup: {
                    select: {
                      season: {
                        select: { id: true, name: true, startDate: true },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    },
  },
  tickerAssists: {
    where: {
      revokedAt: null,
      type: { in: statisticGoalTypes },
    },
    select: {
      id: true,
      ticker: {
        select: {
          event: {
            select: {
              team: {
                select: {
                  ageGroup: {
                    select: {
                      season: {
                        select: { id: true, name: true, startDate: true },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    },
  },
} as const;

type PlayerStatisticSeason = {
  id: string;
  name: string;
  startDate: Date;
};

type PlayerMatchStatisticForCareer = {
  appeared: boolean;
  started: boolean;
  minutesPlayed: number;
  isGoalkeeper: boolean;
  event: {
    matchDetails: {
      status: MatchStatus;
      theirGoals: number | null;
    } | null;
    teamMatchStatistic: { theirGoals: number } | null;
    team: {
      ageGroup: {
        season: PlayerStatisticSeason;
      };
    };
  };
};

type PlayerTickerStatisticForCareer = {
  id: string;
  ticker: {
    event: {
      team: {
        ageGroup: {
          season: PlayerStatisticSeason;
        };
      };
    };
  };
};

function withCareerStatistics<T extends {
  matchStatistics: PlayerMatchStatisticForCareer[];
  tickerGoals: PlayerTickerStatisticForCareer[];
  tickerAssists: PlayerTickerStatisticForCareer[];
  photoAsset?: { id: string; deletedAt: Date | null } | null;
  photoUrl?: string | null;
  consents?: ConsentSnapshot[];
  position?: string | null;
  secondaryPosition?: string | null;
}>(player: T) {
  const {
    matchStatistics,
    tickerGoals,
    tickerAssists,
    photoAsset,
    photoUrl,
    consents,
    ...data
  } = player;
  const bySeason = new Map<
    string,
    {
      seasonId: string;
      seasonName: string;
      seasonStart: Date;
      goals: number;
      assists: number;
      appearances: number;
      starts: number;
      minutes: number;
      cleanSheets: number;
    }
  >();
  const ensureSeason = (season: PlayerStatisticSeason) => {
    const current = bySeason.get(season.id) ?? {
      seasonId: season.id,
      seasonName: season.name,
      seasonStart: season.startDate,
      goals: 0,
      assists: 0,
      appearances: 0,
      starts: 0,
      minutes: 0,
      cleanSheets: 0,
    };
    bySeason.set(season.id, current);
    return current;
  };
  for (const statistic of matchStatistics) {
    const current = ensureSeason(statistic.event.team.ageGroup.season);
    current.appearances += statistic.appeared ? 1 : 0;
    current.starts += statistic.started ? 1 : 0;
    current.minutes += statistic.minutesPlayed;
    const finished =
      statistic.event.matchDetails?.status === MatchStatus.FINISHED ||
      statistic.event.matchDetails?.status === MatchStatus.RECORDED;
    const conceded =
      statistic.event.teamMatchStatistic?.theirGoals ??
      statistic.event.matchDetails?.theirGoals;
    if (
      finished &&
      conceded === 0 &&
      statistic.appeared &&
      isDefensiveProfilePosition(
        player.position,
        player.secondaryPosition,
        statistic.isGoalkeeper,
      )
    ) {
      current.cleanSheets += 1;
    }
  }
  for (const goal of tickerGoals) {
    ensureSeason(goal.ticker.event.team.ageGroup.season).goals += 1;
  }
  for (const assist of tickerAssists) {
    ensureSeason(assist.ticker.event.team.ageGroup.season).assists += 1;
  }
  return {
    ...data,
    photoUrl: hasActiveConsent(consents, ConsentType.PHOTO, 'APP_INTERNAL')
      ? photoAsset && photoAsset.deletedAt === null
        ? mediaAssetUrl(photoAsset.id, '12h')
        : photoUrl ?? null
      : null,
    statistics: {
      goals: tickerGoals.length,
      assists: tickerAssists.length,
      appearances: matchStatistics.filter((item) => item.appeared).length,
      starts: matchStatistics.filter((item) => item.started).length,
      minutes: matchStatistics.reduce(
        (sum, item) => sum + item.minutesPlayed,
        0,
      ),
      cleanSheets: [...bySeason.values()].reduce(
        (sum, item) => sum + item.cleanSheets,
        0,
      ),
      cleanSheetEligible: isDefensiveProfilePosition(
        player.position,
        player.secondaryPosition,
        matchStatistics.some((item) => item.isGoalkeeper),
      ),
    },
    statisticsBySeason: [...bySeason.values()]
      .sort((a, b) => b.seasonStart.getTime() - a.seasonStart.getTime())
      .map(({ seasonStart, ...statistic }) => statistic),
  };
}

function isDefensiveProfilePosition(
  position: string | null | undefined,
  secondaryPosition: string | null | undefined,
  isGoalkeeper: boolean,
) {
  if (isGoalkeeper) return true;
  const value = `${position ?? ''} ${secondaryPosition ?? ''}`.toLocaleUpperCase('de-DE');
  return /(^|\W)(TW|TORHÜTER|TORWART|IV|LV|RV|LIBERO|VERTEIDIGER|ABWEHR)(\W|$)/.test(value);
}

function isGuardianRole(role: Role) {
  return role === Role.PARENT;
}

function isPlayerRole(role: Role) {
  return role === Role.PLAYER;
}

async function guardianLink(userId: string, playerId: string) {
  return prisma.parentPlayerLink.findFirst({
    where: { parentId: userId, playerId },
  });
}

function canManageUnassignedPlayers(role: Role) {
  const roles: Role[] = [
    Role.SUPER_ADMIN,
    Role.CLUB_ADMIN,
    Role.YOUTH_DIRECTOR,
  ];
  return roles.includes(role);
}

async function playerAccessScope(
  user: TeamScopedUser,
): Promise<Prisma.PlayerWhereInput> {
  if (String(user.role) === Role.SUPER_ADMIN) return {};
  if (canManageUnassignedPlayers(user.role as Role)) {
    const clubId = await clubIdForTeam(user.teamId);
    return clubId ? { clubId } : { id: '__no_accessible_players__' };
  }
  const teamIds = await youthPlayerPoolTeamIds(user);
  return { teamId: { in: teamIds } };
}

export async function canAccessPlayer(req: Request, playerId: string) {
  const user = req.user!;
  if (await guardianLink(user.id, playerId)) return true;
  if (isPlayerRole(user.role)) {
    return Boolean(await prisma.player.findFirst({
      where: { id: playerId, userId: user.id },
      select: { id: true },
    }));
  }
  const scope = await playerAccessScope(user);
  const player = await prisma.player.findFirst({
    where: { id: playerId, ...scope },
    select: { id: true },
  });
  return Boolean(player);
}

export async function listPlayers(req: Request, res: Response) {
  const { teamId, role, id: userId } = req.user!;

  if (isPlayerRole(role)) {
    const ownPlayer = await prisma.player.findMany({
      where: { userId, teamId },
      select: publicPlayerSelect,
    });
    return res.json(ownPlayer.map(withCareerStatistics));
  }

  if (isGuardianRole(role)) {
    const links = await prisma.parentPlayerLink.findMany({
      where: { parentId: userId },
      include: { player: { select: publicPlayerSelect } },
      orderBy: { player: { lastName: 'asc' } },
    });
    return res.json(links.map((link) => withCareerStatistics(link.player)));
  }

  const status = parsePlayerStatus(req.query.status);
  const contextTeamIds = await contextualTeamIds(req.user!);
  const scope: Prisma.PlayerWhereInput = { teamId: { in: contextTeamIds } };
  const players = await prisma.player.findMany({
    where: { ...scope, ...(status ? { status } : {}) },
    orderBy: [{ status: 'asc' }, { lastName: 'asc' }, { firstName: 'asc' }],
    select: publicPlayerSelect,
  });
  return res.json(players.map(withCareerStatistics));
}

export async function getPlayer(req: Request, res: Response) {
  const user = req.user!;
  const { id } = req.params;
  if (!(await canAccessPlayer(req, id))) {
    return res.status(404).json({ message: 'Spielerprofil nicht gefunden.' });
  }

  const guardian = await guardianLink(user.id, id);
  const canViewSensitive =
    hasPermission(user.role, Permission.VIEW_SENSITIVE_PLAYER) ||
    guardian?.isLegalGuardian === true ||
    isPlayerRole(user.role);
  const canViewStaffNotes = hasPermission(user.role, Permission.MANAGE_DEVELOPMENT);

  const player = await prisma.player.findUnique({
    where: { id },
    select: {
      ...publicPlayerSelect,
      team: {
        select: {
          id: true,
          name: true,
          ageGroup: { select: { id: true, name: true, code: true } },
        },
      },
      photoAsset: {
        select: { id: true, pathname: true, deletedAt: true },
      },
      photoUrl: true,
      parentLinks: {
        select: {
          id: true,
          relationship: true,
          isLegalGuardian: true,
          canPickup: true,
          receivesCommunication: true,
          parent: {
            select: { id: true, name: true, email: true, phone: true },
          },
        },
      },
      medicalProfile: canViewSensitive,
      emergencyContacts: canViewSensitive
        ? { orderBy: [{ priority: 'asc' }, { name: 'asc' }] }
        : false,
      consents: canViewSensitive
        ? {
            orderBy: { type: 'asc' },
            include: {
              evidence: {
                orderBy: { createdAt: 'desc' },
                take: 10,
                select: {
                  id: true,
                  action: true,
                  templateVersion: true,
                  signerName: true,
                  documentHash: true,
                  statement: true,
                  createdAt: true,
                },
              },
            },
          }
        : false,
      developmentNotes: {
        where: canViewStaffNotes
          ? {}
          : guardian || isPlayerRole(user.role)
            ? { visibility: 'GUARDIANS_AND_STAFF' }
            : { id: '__no_visible_development_notes__' },
        orderBy: { observedAt: 'desc' },
        include: { author: { select: { id: true, name: true } } },
      },
    },
  });

  const photoConsent = hasActiveConsent(
    player?.consents as ConsentSnapshot[] | undefined,
    ConsentType.PHOTO,
    'APP_INTERNAL',
  );
  const medicalConsent = hasActiveConsent(
    player?.consents as ConsentSnapshot[] | undefined,
    ConsentType.MEDICAL_DATA,
  );
  const serialized = player ? withCareerStatistics(player) : player;
  return res.json({
    ...serialized,
    photoAsset: undefined,
    consents: canViewSensitive ? player?.consents : undefined,
    medicalProfile: canViewSensitive
      ? medicalProfileForConsent(
          player?.medicalProfile,
          player?.consents as ConsentSnapshot[] | undefined,
          guardian?.isLegalGuardian !== true && !isPlayerRole(user.role),
        )
      : undefined,
    capabilities: {
      canEdit: hasPermission(user.role, Permission.MANAGE_PLAYERS),
      canViewSensitive,
      canEditSensitive:
        medicalConsent &&
        (hasPermission(user.role, Permission.MANAGE_SENSITIVE_PLAYER) ||
          guardian?.isLegalGuardian === true),
      canDigitallyConsent: guardian?.isLegalGuardian === true,
      canManageDocuments:
        hasPermission(user.role, Permission.MANAGE_DOCUMENTS) ||
        guardian?.isLegalGuardian === true,
      canManagePhoto:
        photoConsent &&
        (hasPermission(user.role, Permission.MANAGE_PLAYERS) ||
          guardian?.isLegalGuardian === true),
      canAddDevelopment: hasPermission(user.role, Permission.MANAGE_DEVELOPMENT),
    },
  });
}

export async function createPlayer(req: Request, res: Response) {
  const { teamId: defaultTeamId, id: actorId } = req.user!;
  const allowedTeamIds = await accessibleTeamIds(req.user!);
  const requestedTeamId =
    typeof req.body?.teamId === 'string' ? req.body.teamId.trim() : defaultTeamId;
  if (!requestedTeamId || !allowedTeamIds.includes(requestedTeamId)) {
    return res.status(403).json({ message: 'Diese Mannschaft darf nicht verwaltet werden.' });
  }
  const targetTeam = await prisma.team.findFirst({
    where: {
      id: requestedTeamId,
      isActive: true,
      deletedAt: null,
    },
    select: {
      ageGroup: {
        select: { season: { select: { clubId: true } } },
      },
    },
  });
  if (!targetTeam) {
    return res.status(404).json({ message: 'Zielmannschaft nicht gefunden.' });
  }
  const data = playerData(req.body);
  if (!data.firstName || !data.lastName) {
    return res.status(400).json({ message: 'Vor- und Nachname sind erforderlich.' });
  }

  const player = await prisma.$transaction(async (tx) => {
    const created = await tx.player.create({
      data: {
        ...data,
        clubId: targetTeam.ageGroup.season.clubId,
        teamId: requestedTeamId,
      },
      select: publicPlayerSelect,
    });
    await tx.auditLog.create({
      data: {
        actorId,
        teamId: requestedTeamId,
        action: 'PLAYER_CREATED',
        entityType: 'Player',
        entityId: created.id,
        metadata: { name: `${created.firstName} ${created.lastName}` },
      },
    });
    return created;
  });

  return res.status(201).json(withCareerStatistics(player));
}

export async function updatePlayer(req: Request, res: Response) {
  const { id: actorId } = req.user!;
  const { id } = req.params;
  const scope = await playerAccessScope(req.user!);
  const teamIds = await accessibleTeamIds(req.user!);
  const player = await prisma.player.findFirst({
    where: { id, ...scope },
  });
  if (!player) return res.status(404).json({ message: 'Spielerprofil nicht gefunden.' });
  const requestedTeamId =
    typeof req.body?.teamId === 'string' ? req.body.teamId.trim() : player.teamId;
  if (!requestedTeamId || !teamIds.includes(requestedTeamId)) {
    return res.status(403).json({ message: 'Die Zielmannschaft darf nicht verwaltet werden.' });
  }
  const targetTeam = await prisma.team.findFirst({
    where: {
      id: requestedTeamId,
      isActive: true,
      deletedAt: null,
    },
    select: {
      ageGroup: {
        select: { season: { select: { clubId: true } } },
      },
    },
  });
  if (!targetTeam || targetTeam.ageGroup.season.clubId !== player.clubId) {
    return res.status(403).json({
      message: 'Der Spieler darf nur einer Mannschaft desselben Vereins zugeordnet werden.',
    });
  }

  const updated = await prisma.$transaction(async (tx) => {
    const result = await tx.player.update({
      where: { id },
      data: {
        ...Object.fromEntries(
          Object.entries(playerData(req.body)).filter(
            ([key, value]) => req.body[key] !== undefined && value !== undefined,
          ),
        ),
        teamId: requestedTeamId,
      },
      select: publicPlayerSelect,
    });
    await tx.auditLog.create({
      data: {
        actorId,
        teamId: requestedTeamId,
        action: 'PLAYER_UPDATED',
        entityType: 'Player',
        entityId: id,
        metadata: {
          previousTeamId: player.teamId,
          teamId: requestedTeamId,
          moved: player.teamId !== requestedTeamId,
        },
      },
    });
    return result;
  });

  return res.json(withCareerStatistics(updated));
}

export async function upsertMedicalProfile(req: Request, res: Response) {
  const user = req.user!;
  const { id } = req.params;
  if (!(await canAccessPlayer(req, id))) {
    return res.status(404).json({ message: 'Spielerprofil nicht gefunden.' });
  }
  const guardian = await guardianLink(user.id, id);
  if (
    !hasPermission(user.role, Permission.MANAGE_SENSITIVE_PLAYER) &&
    guardian?.isLegalGuardian !== true
  ) {
    return res.status(403).json({ message: 'Keine Berechtigung für Gesundheitsdaten.' });
  }

  const fields = [
    'allergies',
    'medications',
    'conditions',
    'physicianName',
    'physicianPhone',
    'emergencyNotes',
  ] as const;
  const data = Object.fromEntries(
    fields.map((field) => [field, cleanOptionalString(req.body[field])]),
  );
  const requiredSelections = new Set<string>();
  if (data.allergies) requiredSelections.add('ALLERGIES');
  if (data.medications) requiredSelections.add('MEDICATION');
  if (data.conditions) requiredSelections.add('CONDITIONS');
  if (data.physicianName || data.physicianPhone || data.emergencyNotes) {
    requiredSelections.add('EMERGENCY');
  }
  const consent = await prisma.playerConsent.findUnique({
    where: { playerId_type: { playerId: id, type: ConsentType.MEDICAL_DATA } },
    select: {
      type: true,
      status: true,
      expiresAt: true,
      evidence: {
        where: { action: ConsentStatus.GRANTED },
        orderBy: { createdAt: 'desc' },
        take: 1,
        select: { action: true, statement: true, createdAt: true },
      },
    },
  });
  const consentList = consent ? [consent] : [];
  const missingSelection = [...requiredSelections].find(
    (selection) =>
      !hasActiveConsent(consentList, ConsentType.MEDICAL_DATA, selection),
  );
  if (missingSelection) {
    return res.status(409).json({
      message:
        'Diese Gesundheitsangabe ist nicht vom aktuell unterschriebenen Einwilligungsumfang abgedeckt.',
      code: 'MEDICAL_CONSENT_REQUIRED',
    });
  }
  if (
    requiredSelections.size > 0 &&
    guardian?.isLegalGuardian !== true &&
    !hasActiveConsent(consentList, ConsentType.MEDICAL_DATA, 'AUTHORIZED_STAFF')
  ) {
    return res.status(409).json({
      message:
        'Die Einwilligung erlaubt aktuell keinen Zugriff durch Trainer oder Vereinsverantwortliche.',
      code: 'MEDICAL_STAFF_CONSENT_REQUIRED',
    });
  }
  const medical = await prisma.$transaction(async (tx) => {
    const result = await tx.playerMedicalProfile.upsert({
      where: { playerId: id },
      update: { ...data, updatedById: user.id },
      create: { ...data, playerId: id, updatedById: user.id },
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: user.teamId,
        action: 'PLAYER_MEDICAL_UPDATED',
        entityType: 'Player',
        entityId: id,
      },
    });
    return result;
  });
  return res.json(medical);
}

export async function createEmergencyContact(req: Request, res: Response) {
  const user = req.user!;
  const { id } = req.params;
  if (!(await canAccessPlayer(req, id))) {
    return res.status(404).json({ message: 'Spielerprofil nicht gefunden.' });
  }
  const guardian = await guardianLink(user.id, id);
  if (
    !hasPermission(user.role, Permission.MANAGE_SENSITIVE_PLAYER) &&
    guardian?.isLegalGuardian !== true
  ) {
    return res.status(403).json({ message: 'Keine Berechtigung für Notfallkontakte.' });
  }
  const { name, phone, relationship, priority, isAuthorizedPickup } = req.body;
  if (!name?.trim() || !phone?.trim()) {
    return res.status(400).json({ message: 'Name und Telefonnummer sind erforderlich.' });
  }
  const contact = await prisma.playerEmergencyContact.create({
    data: {
      playerId: id,
      name: name.trim(),
      phone: phone.trim(),
      relationship: cleanOptionalString(relationship),
      priority: Number.isInteger(priority) ? Math.max(1, priority) : 1,
      isAuthorizedPickup: isAuthorizedPickup === true,
    },
  });
  return res.status(201).json(contact);
}

export async function addDevelopmentNote(req: Request, res: Response) {
  const user = req.user!;
  const { id } = req.params;
  if (!(await canAccessPlayer(req, id))) {
    return res.status(404).json({ message: 'Spielerprofil nicht gefunden.' });
  }
  const { title, notes, category, visibility, rating, observedAt } = req.body;
  if (!title?.trim() || !notes?.trim()) {
    return res.status(400).json({ message: 'Titel und Beobachtung sind erforderlich.' });
  }
  const normalizedRating =
    Number.isInteger(rating) && rating >= 1 && rating <= 5 ? rating : null;
  const entry = await prisma.playerDevelopmentNote.create({
    data: {
      playerId: id,
      authorId: user.id,
      title: title.trim(),
      notes: notes.trim(),
      category: validDevelopmentCategory(category),
      visibility:
        visibility === 'GUARDIANS_AND_STAFF' ? 'GUARDIANS_AND_STAFF' : 'STAFF_ONLY',
      rating: normalizedRating,
      observedAt: validDate(observedAt) ?? new Date(),
    },
    include: { author: { select: { id: true, name: true } } },
  });
  return res.status(201).json(entry);
}

export async function upsertConsent(req: Request, res: Response) {
  const user = req.user!;
  const { id, type } = req.params;
  if (!(await canAccessPlayer(req, id))) {
    return res.status(404).json({ message: 'Spielerprofil nicht gefunden.' });
  }
  const guardian = await guardianLink(user.id, id);
  if (
    !hasPermission(user.role, Permission.MANAGE_SENSITIVE_PLAYER) &&
    guardian?.isLegalGuardian !== true
  ) {
    return res.status(403).json({ message: 'Keine Berechtigung für Einwilligungen.' });
  }
  const consentType = validConsentType(type);
  if (!consentType) {
    return res.status(400).json({ message: 'Unbekannte Einwilligungsart.' });
  }
  const status = validConsentStatus(req.body.status);
  if (status === 'GRANTED') {
    return res.status(409).json({
      message:
        'Eine Einwilligung kann nur über die aktuelle Vorlage und eine digitale Unterschrift erteilt werden.',
      code: 'DIGITAL_CONSENT_REQUIRED',
    });
  }
  if (status === 'REVOKED') {
    return res.status(409).json({
      message: 'Bitte den dokumentierten Widerruf verwenden.',
      code: 'DOCUMENTED_REVOCATION_REQUIRED',
    });
  }
  const now = new Date();
  const consent = await prisma.$transaction(async (tx) => {
    const result = await tx.playerConsent.upsert({
      where: { playerId_type: { playerId: id, type: consentType } },
      update: {
        status,
        revokedAt: null,
        expiresAt: validDate(req.body.expiresAt),
        note: cleanOptionalString(req.body.note),
      },
      create: {
        playerId: id,
        type: consentType,
        status,
        grantedBy: null,
        grantedAt: null,
        revokedAt: null,
        expiresAt: validDate(req.body.expiresAt),
        note: cleanOptionalString(req.body.note),
      },
    });
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        teamId: user.teamId,
        action: `PLAYER_CONSENT_${status}`,
        entityType: 'PlayerConsent',
        entityId: result.id,
        metadata: { playerId: id, type: consentType },
      },
    });
    return result;
  });
  return res.json(consent);
}

export async function deletePlayer(req: Request, res: Response) {
  const { id: actorId } = req.user!;
  const { id } = req.params;
  const scope = await playerAccessScope(req.user!);
  const player = await prisma.player.findFirst({
    where: { id, ...scope },
  });
  if (!player) return res.status(404).json({ message: 'Spielerprofil nicht gefunden.' });

  await prisma.$transaction(async (tx) => {
    await tx.auditLog.create({
      data: {
        actorId,
        teamId: player.teamId ?? req.user!.teamId,
        action: 'PLAYER_DELETED',
        entityType: 'Player',
        entityId: id,
        metadata: { name: `${player.firstName} ${player.lastName}` },
      },
    });
    await tx.player.delete({ where: { id } });
  });
  return res.status(204).send();
}

export function playerData(body: Record<string, unknown>) {
  return {
    firstName: cleanRequiredString(body.firstName),
    lastName: cleanRequiredString(body.lastName),
    preferredName: cleanOptionalString(body.preferredName),
    birthDate: validDate(body.birthDate),
    nationality: cleanOptionalString(body.nationality),
    gender: parsePlayerGender(body.gender),
    position: cleanOptionalString(body.position),
    secondaryPosition: cleanOptionalString(body.secondaryPosition),
    dominantFoot: parseDominantFoot(body.dominantFoot) ?? DominantFoot.UNKNOWN,
    shirtNumber:
      Number.isInteger(body.shirtNumber) && Number(body.shirtNumber) > 0
        ? Number(body.shirtNumber)
        : null,
    passNumber: cleanOptionalString(body.passNumber),
    status: parsePlayerStatus(body.status) ?? PlayerStatus.ACTIVE,
    joinedAt: validDate(body.joinedAt),
  };
}

function cleanRequiredString(value: unknown) {
  return typeof value === 'string' ? value.trim() : '';
}

function cleanOptionalString(value: unknown) {
  if (value === null) return null;
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function validDate(value: unknown) {
  if (value === null || value === undefined || value === '') return null;
  const date = new Date(String(value));
  return Number.isNaN(date.valueOf()) ? null : date;
}

function parsePlayerStatus(value: unknown) {
  return typeof value === 'string' &&
    Object.values(PlayerStatus).includes(value as PlayerStatus)
    ? (value as PlayerStatus)
    : null;
}

function parseDominantFoot(value: unknown) {
  return typeof value === 'string' &&
    Object.values(DominantFoot).includes(value as DominantFoot)
    ? (value as DominantFoot)
    : null;
}

function parsePlayerGender(value: unknown) {
  if (value === null || value === '') return null;
  return typeof value === 'string' &&
    Object.values(PlayerGender).includes(value as PlayerGender)
    ? (value as PlayerGender)
    : null;
}

function validDevelopmentCategory(value: unknown) {
  return [
    'TECHNIQUE',
    'TACTICS',
    'ATHLETIC',
    'SOCIAL',
    'GOALKEEPING',
    'GENERAL',
  ].includes(String(value))
    ? (value as
        | 'TECHNIQUE'
        | 'TACTICS'
        | 'ATHLETIC'
        | 'SOCIAL'
        | 'GOALKEEPING'
        | 'GENERAL')
    : 'GENERAL';
}

function validConsentType(value: unknown) {
  return ['PHOTO', 'TEAM_PHOTO', 'TRANSPORT', 'MEDICAL_DATA', 'COMMUNICATION'].includes(
    String(value),
  )
    ? (value as 'PHOTO' | 'TEAM_PHOTO' | 'TRANSPORT' | 'MEDICAL_DATA' | 'COMMUNICATION')
    : null;
}

function validConsentStatus(value: unknown) {
  return ['GRANTED', 'REVOKED', 'EXPIRED'].includes(String(value))
    ? (value as 'GRANTED' | 'REVOKED' | 'EXPIRED')
    : 'PENDING';
}
