import jwt, { Secret, SignOptions } from 'jsonwebtoken';

const ACCESS_SECRET: Secret = process.env.ACCESS_TOKEN_SECRET || 'access_secret';
const REFRESH_SECRET: Secret = process.env.REFRESH_TOKEN_SECRET || 'refresh_secret';

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
