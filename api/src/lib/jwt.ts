import { createHmac } from 'crypto';
import jwt, { Secret, SignOptions } from 'jsonwebtoken';

const isProduction = process.env.NODE_ENV === 'production';
const minimumSecretLength = 32;

function requiredSecret(name: string, legacyName?: string): string {
  const value = process.env[name] || (legacyName ? process.env[legacyName] : undefined);
  if (!value) {
    if (isProduction) {
      throw new Error(`${name} must be configured in production`);
    }
    return `development-only-${name.toLowerCase()}-secret-change-me`;
  }
  if (isProduction && value.length < minimumSecretLength) {
    throw new Error(`${name} must contain at least ${minimumSecretLength} characters`);
  }
  return value;
}

function purposeSecret(explicitValue: string | undefined, purpose: string, root: string): string {
  if (explicitValue) {
    if (isProduction && explicitValue.length < minimumSecretLength) {
      throw new Error(`${purpose} secret must contain at least ${minimumSecretLength} characters`);
    }
    return explicitValue;
  }
  return createHmac('sha256', root)
    .update(`fc-teugn-talents:${purpose}:v1`)
    .digest('base64url');
}

const accessSecret = requiredSecret('ACCESS_TOKEN_SECRET', 'JWT_SECRET');
const refreshSecret = requiredSecret('REFRESH_TOKEN_SECRET');
if (isProduction && accessSecret === refreshSecret) {
  throw new Error('ACCESS_TOKEN_SECRET and REFRESH_TOKEN_SECRET must be different');
}

const ACCESS_SECRET: Secret = accessSecret;
const REFRESH_SECRET: Secret = refreshSecret;
const EMERGENCY_SECRET: Secret = purposeSecret(
  process.env.EMERGENCY_ACCESS_SECRET,
  'emergency-access',
  accessSecret,
);
const MEDIA_SECRET: Secret = purposeSecret(
  process.env.MEDIA_ACCESS_SECRET,
  'media-access',
  accessSecret,
);

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
