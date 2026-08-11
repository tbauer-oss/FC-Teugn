import { ConsentStatus, ConsentType, Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma';

export type ConsentSnapshot = {
  type: ConsentType;
  status: ConsentStatus;
  expiresAt: Date | null;
  evidence?: Array<{
    action: ConsentStatus;
    statement?: Prisma.JsonValue;
    createdAt?: Date;
  }>;
};

function selectedOptions(consent: ConsentSnapshot) {
  const evidence = consent.evidence?.find(
    (item) => item.action === ConsentStatus.GRANTED,
  );
  const statement = evidence?.statement;
  if (!statement || typeof statement !== 'object' || Array.isArray(statement)) {
    return new Set<string>();
  }
  const selections = (statement as Record<string, unknown>).selections;
  if (!Array.isArray(selections)) return new Set<string>();
  return new Set(
    selections.filter((item): item is string => typeof item === 'string'),
  );
}

function documentedSelections(consent: ConsentSnapshot) {
  const evidence = consent.evidence?.find(
    (item) => item.action === ConsentStatus.GRANTED,
  );
  if (!evidence) return null;
  return selectedOptions(consent);
}

export function hasActiveConsent(
  consents: readonly ConsentSnapshot[] | null | undefined,
  type: ConsentType,
  requiredSelection?: string,
) {
  const now = Date.now();
  const consent = consents?.find(
    (item) =>
      item.type === type &&
      item.status === ConsentStatus.GRANTED &&
      (!item.expiresAt || item.expiresAt.getTime() > now),
  );
  if (!consent) return false;
  return requiredSelection
    ? selectedOptions(consent).has(requiredSelection)
    : true;
}

export async function playerHasActiveConsent(
  playerId: string,
  type: ConsentType,
  requiredSelection?: string,
) {
  const consent = await prisma.playerConsent.findUnique({
    where: { playerId_type: { playerId, type } },
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
  return hasActiveConsent(consent ? [consent] : [], type, requiredSelection);
}

/**
 * Missing, pending or expired consent records are not interpreted as an
 * objection to an internally stored team photo. The photo is blocked only by
 * a documented withdrawal/refusal or by a signed decision that deliberately
 * omits the protected app scope.
 */
export function explicitlyBlocksTeamPhoto(
  consents: readonly ConsentSnapshot[] | null | undefined,
) {
  const consent = consents?.find(
    (item) => item.type === ConsentType.TEAM_PHOTO,
  );
  if (!consent) return false;
  if (consent.status === ConsentStatus.REVOKED) return true;
  if (consent.status !== ConsentStatus.GRANTED) return false;
  const selections = documentedSelections(consent);
  return selections !== null && !selections.has('APP_INTERNAL');
}

export async function teamPhotoConsentStatus(teamId: string) {
  const players = await prisma.player.findMany({
    where: { teamId, status: 'ACTIVE' },
    select: {
      id: true,
      firstName: true,
      lastName: true,
      consents: {
        where: { type: ConsentType.TEAM_PHOTO },
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
      },
    },
  });
  const blocking = players.filter((player) =>
    explicitlyBlocksTeamPhoto(player.consents),
  );
  return {
    allowed: blocking.length === 0,
    playerCount: players.length,
    blocking: blocking.map((player) => ({
      id: player.id,
      name: `${player.firstName} ${player.lastName}`,
    })),
  };
}

export function medicalProfileForConsent<T extends {
  allergies: string | null;
  medications: string | null;
  conditions: string | null;
  physicianName: string | null;
  physicianPhone: string | null;
  emergencyNotes: string | null;
}>(
  profile: T | null | undefined,
  consents: readonly ConsentSnapshot[] | null | undefined,
  requireAuthorizedStaff: boolean,
) {
  if (!profile || !hasActiveConsent(consents, ConsentType.MEDICAL_DATA)) {
    return null;
  }
  if (
    requireAuthorizedStaff &&
    !hasActiveConsent(consents, ConsentType.MEDICAL_DATA, 'AUTHORIZED_STAFF')
  ) {
    return null;
  }
  return {
    ...profile,
    allergies: hasActiveConsent(consents, ConsentType.MEDICAL_DATA, 'ALLERGIES')
      ? profile.allergies
      : null,
    medications: hasActiveConsent(consents, ConsentType.MEDICAL_DATA, 'MEDICATION')
      ? profile.medications
      : null,
    conditions: hasActiveConsent(consents, ConsentType.MEDICAL_DATA, 'CONDITIONS')
      ? profile.conditions
      : null,
    physicianName: hasActiveConsent(consents, ConsentType.MEDICAL_DATA, 'EMERGENCY')
      ? profile.physicianName
      : null,
    physicianPhone: hasActiveConsent(consents, ConsentType.MEDICAL_DATA, 'EMERGENCY')
      ? profile.physicianPhone
      : null,
    emergencyNotes: hasActiveConsent(consents, ConsentType.MEDICAL_DATA, 'EMERGENCY')
      ? profile.emergencyNotes
      : null,
  };
}
