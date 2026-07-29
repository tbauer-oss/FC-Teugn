import jwt, { Secret, SignOptions } from 'jsonwebtoken';

const ACCESS_SECRET: Secret =
  process.env.ACCESS_TOKEN_SECRET || process.env.JWT_SECRET || 'access_secret';
const REFRESH_SECRET: Secret = process.env.REFRESH_TOKEN_SECRET || 'refresh_secret';
const EMERGENCY_SECRET: Secret =
  process.env.EMERGENCY_ACCESS_SECRET || `${String(ACCESS_SECRET)}:emergency`;
const MEDIA_SECRET: Secret =
  process.env.MEDIA_ACCESS_SECRET || `${String(ACCESS_SECRET)}:media`;

function signToken(payload: object, secret: Secret, expiresIn: SignOptions['expiresIn']) {
  const options: SignOptions = { expiresIn };
  return jwt.sign(payload, secret, options);
}

export function signAccessToken(payload: object, expiresIn: SignOptions['expiresIn'] = '15m') {
  return signToken(payload, ACCESS_SECRET, expiresIn);
}

export function signRefreshToken(payload: object, expiresIn: SignOptions['expiresIn'] = '30d') {
  return signToken(payload, REFRESH_SECRET, expiresIn);
}

export function verifyAccessToken(token: string) {
  return jwt.verify(token, ACCESS_SECRET);
}

export function verifyRefreshToken(token: string) {
  return jwt.verify(token, REFRESH_SECRET);
}

export function verifyRefresh(token: string) {
  return jwt.verify(token, REFRESH_SECRET);
}

export interface EmergencyAccessClaims {
  kind: 'emergency-access';
  userId: string;
  eventId: string;
}

export function signEmergencyAccessToken(
  payload: Omit<EmergencyAccessClaims, 'kind'>,
  expiresIn: SignOptions['expiresIn'] = '5m',
) {
  return signToken({ ...payload, kind: 'emergency-access' }, EMERGENCY_SECRET, expiresIn);
}

export function verifyEmergencyAccessToken(token: string) {
  const decoded = jwt.verify(token, EMERGENCY_SECRET) as EmergencyAccessClaims;
  if (
    decoded.kind !== 'emergency-access' ||
    typeof decoded.userId !== 'string' ||
    typeof decoded.eventId !== 'string'
  ) {
    throw new Error('Invalid emergency access token');
  }
  return decoded;
}

export interface MediaAccessClaims {
  kind: 'media-access';
  assetId: string;
}

export function signMediaAccessToken(
  payload: Omit<MediaAccessClaims, 'kind'>,
  expiresIn: SignOptions['expiresIn'] = '15m',
) {
  return signToken({ ...payload, kind: 'media-access' }, MEDIA_SECRET, expiresIn);
}

export function verifyMediaAccessToken(token: string) {
  const decoded = jwt.verify(token, MEDIA_SECRET) as MediaAccessClaims;
  if (decoded.kind !== 'media-access' || typeof decoded.assetId !== 'string') {
    throw new Error('Invalid media access token');
  }
  return decoded;
}
