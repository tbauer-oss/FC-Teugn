export const refreshRotationGraceMs = 15_000;

export function isRecentRefreshRotation(
  revokedAt: Date | null | undefined,
  now = new Date(),
) {
  if (!revokedAt) return false;
  const age = now.getTime() - revokedAt.getTime();
  return age >= 0 && age <= refreshRotationGraceMs;
}
