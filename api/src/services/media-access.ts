import { SignOptions } from 'jsonwebtoken';
import {
  signMediaAccessToken,
  verifyMediaAccessToken,
} from '../lib/jwt';

function apiPublicUrl() {
  const explicit = process.env.API_PUBLIC_URL?.trim();
  if (explicit) return explicit.replace(/\/+$/, '');

  const vercelHost =
    process.env.VERCEL_PROJECT_PRODUCTION_URL?.trim() ||
    process.env.VERCEL_URL?.trim();
  if (vercelHost) {
    return `https://${vercelHost.replace(/^https?:\/\//, '').replace(/\/+$/, '')}`;
  }

  if (process.env.NODE_ENV !== 'production') {
    return `http://localhost:${process.env.PORT || 4000}`;
  }
  return 'https://fc-teugn-backend.vercel.app';
}

export function mediaAssetUrl(
  assetId: string,
  expiresIn: SignOptions['expiresIn'] = '15m',
) {
  const token = signMediaAccessToken({ assetId }, expiresIn);
  return `${apiPublicUrl()}/media/${encodeURIComponent(assetId)}?token=${encodeURIComponent(token)}`;
}

export { verifyMediaAccessToken };
