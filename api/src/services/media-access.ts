import { SignOptions } from 'jsonwebtoken';
import {
  signMediaAccessToken,
  verifyMediaAccessToken,
} from '../lib/jwt';

export function apiPublicUrl() {
  const explicit = process.env.API_PUBLIC_URL?.trim();
  if (explicit) return explicit.replace(/\/+$/, '');

  if (process.env.NODE_ENV !== 'production') {
    return `http://localhost:${process.env.PORT || 4000}`;
  }
  return 'https://app.fc-teugn-talents.de/api';
}

export function playingCommunityLogoUrl(teamId: string, assetId?: string) {
  const version = assetId ? `?v=${encodeURIComponent(assetId)}` : '';
  return `${apiPublicUrl()}/media/playing-community-logo/${encodeURIComponent(teamId)}${version}`;
}

export function mediaAssetUrl(
  assetId: string,
  expiresIn: SignOptions['expiresIn'] = '15m',
) {
  const token = signMediaAccessToken({ assetId }, expiresIn);
  return `${apiPublicUrl()}/media/${encodeURIComponent(assetId)}?token=${encodeURIComponent(token)}`;
}

export { verifyMediaAccessToken };
