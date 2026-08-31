export const playerInjuryTypes = [
  'CONTUSION',
  'SUPERFICIAL_INJURY',
  'MUSCLE_DISCOMFORT',
  'STRAIN',
  'MUSCLE_FIBER_TEAR',
  'MUSCLE_BUNDLE_TEAR',
  'THIGH_INJURY',
  'CALF_INJURY',
  'GROIN_ADDUCTOR_INJURY',
  'SPRAIN_DISTORTION',
  'ANKLE_INJURY',
  'LIGAMENT_STRETCH',
  'LIGAMENT_TEAR',
  'KNEE_INJURY',
  'MENISCUS_INJURY',
  'KNEE_COLLATERAL_LIGAMENT',
  'ACL_INJURY',
  'PATELLAR_KNEECAP_COMPLAINT',
  'FOOT_TOE_INJURY',
  'FRACTURE',
  'BACK_COMPLAINT',
  'SHOULDER_ARM_INJURY',
  'HEAD_INJURY_CONCUSSION',
  'HEAD_INJURY',
  'OTHER',
  // Bestehende Werte bleiben für ältere Datensätze und Clients gültig.
  'MUSCLE_INJURY',
  'LIGAMENT_INJURY',
  'JOINT_INJURY',
  'OVERUSE',
  'ILLNESS',
] as const;

export type PlayerInjuryType = (typeof playerInjuryTypes)[number];

export const playerInjurySeverities = [
  'UNKNOWN',
  'LIGHT',
  'MEDIUM',
  'SEVERE',
] as const;

export type PlayerInjurySeverity = (typeof playerInjurySeverities)[number];

type RecoveryRange = { minDays: number; maxDays: number };

const typicalRanges: Partial<Record<PlayerInjuryType, RecoveryRange>> = {
  CONTUSION: { minDays: 3, maxDays: 14 },
  SUPERFICIAL_INJURY: { minDays: 2, maxDays: 10 },
  MUSCLE_DISCOMFORT: { minDays: 3, maxDays: 14 },
  STRAIN: { minDays: 7, maxDays: 21 },
  MUSCLE_FIBER_TEAR: { minDays: 21, maxDays: 42 },
  MUSCLE_BUNDLE_TEAR: { minDays: 42, maxDays: 84 },
  THIGH_INJURY: { minDays: 7, maxDays: 42 },
  CALF_INJURY: { minDays: 7, maxDays: 42 },
  GROIN_ADDUCTOR_INJURY: { minDays: 7, maxDays: 42 },
  SPRAIN_DISTORTION: { minDays: 7, maxDays: 21 },
  ANKLE_INJURY: { minDays: 7, maxDays: 42 },
  LIGAMENT_STRETCH: { minDays: 7, maxDays: 21 },
  LIGAMENT_TEAR: { minDays: 42, maxDays: 84 },
  KNEE_INJURY: { minDays: 14, maxDays: 84 },
  MENISCUS_INJURY: { minDays: 42, maxDays: 168 },
  KNEE_COLLATERAL_LIGAMENT: { minDays: 21, maxDays: 84 },
  ACL_INJURY: { minDays: 180, maxDays: 365 },
  PATELLAR_KNEECAP_COMPLAINT: { minDays: 14, maxDays: 84 },
  FOOT_TOE_INJURY: { minDays: 7, maxDays: 56 },
  FRACTURE: { minDays: 42, maxDays: 112 },
  BACK_COMPLAINT: { minDays: 7, maxDays: 42 },
  SHOULDER_ARM_INJURY: { minDays: 14, maxDays: 56 },
  MUSCLE_INJURY: { minDays: 7, maxDays: 42 },
  LIGAMENT_INJURY: { minDays: 21, maxDays: 84 },
  JOINT_INJURY: { minDays: 7, maxDays: 42 },
  OVERUSE: { minDays: 7, maxDays: 42 },
};

export function validInjuryType(value: unknown): PlayerInjuryType | null {
  const normalized = typeof value === 'string' ? value.trim().toUpperCase() : '';
  return playerInjuryTypes.includes(normalized as PlayerInjuryType)
    ? (normalized as PlayerInjuryType)
    : null;
}

export function validInjurySeverity(value: unknown): PlayerInjurySeverity {
  const normalized = typeof value === 'string' ? value.trim().toUpperCase() : '';
  return playerInjurySeverities.includes(normalized as PlayerInjurySeverity)
    ? (normalized as PlayerInjurySeverity)
    : 'UNKNOWN';
}

export function estimateInjuryRecovery(
  injuryType: PlayerInjuryType | null,
  severity: PlayerInjurySeverity = 'UNKNOWN',
): RecoveryRange | null {
  if (!injuryType) return null;
  const range = typicalRanges[injuryType];
  if (!range) return null;

  const factor = severity === 'LIGHT' ? 0.8 : severity === 'SEVERE' ? 1.5 : 1;
  return {
    minDays: Math.max(1, Math.round(range.minDays * factor)),
    maxDays: Math.max(2, Math.round(range.maxDays * factor)),
  };
}

export function addDays(date: Date, days: number) {
  const result = new Date(date);
  result.setUTCDate(result.getUTCDate() + days);
  return result;
}
