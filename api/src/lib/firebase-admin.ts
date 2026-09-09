import {
  App,
  applicationDefault,
  cert,
  getApps,
  initializeApp,
} from 'firebase-admin/app';
import { Messaging, getMessaging } from 'firebase-admin/messaging';
import { externalDeliveriesAllowed } from './runtime-environment';

export type FirebaseServiceAccount = {
  projectId: string;
  clientEmail: string;
  privateKey: string;
};

export function parseFirebaseServiceAccount(raw: string): FirebaseServiceAccount {
  const parsed = JSON.parse(raw) as Record<string, unknown>;
  const projectId = String(parsed.project_id ?? '').trim();
  const clientEmail = String(parsed.client_email ?? '').trim();
  const privateKey = String(parsed.private_key ?? '').replace(/\\n/g, '\n').trim();
  if (!projectId || !clientEmail || !privateKey.includes('PRIVATE KEY')) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON is incomplete.');
  }
  return { projectId, clientEmail, privateKey };
}

let cachedApp: App | null = null;
let configurationFailed = false;

function cloudProjectId() {
  return (
    process.env.GOOGLE_CLOUD_PROJECT?.trim() ||
    process.env.GCLOUD_PROJECT?.trim() ||
    process.env.FIREBASE_PROJECT_ID?.trim() ||
    ''
  );
}

function runningOnGoogleCloud() {
  return Boolean(
    process.env.K_SERVICE ||
      process.env.GOOGLE_CLOUD_PROJECT ||
      process.env.GCLOUD_PROJECT,
  );
}

function firebaseApp(): App | null {
  if (cachedApp) return cachedApp;
  if (configurationFailed) return null;

  const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
  try {
    if (raw) {
      const serviceAccount = parseFirebaseServiceAccount(raw);
      cachedApp =
        getApps().find((app) => app.name === 'fc-teugn-push') ??
        initializeApp(
          {
            credential: cert(serviceAccount),
            projectId: serviceAccount.projectId,
          },
          'fc-teugn-push',
        );
      return cachedApp;
    }

    if (runningOnGoogleCloud()) {
      const projectId = cloudProjectId();
      cachedApp =
        getApps().find((app) => app.name === 'fc-teugn-push') ??
        initializeApp(
          {
            credential: applicationDefault(),
            ...(projectId ? { projectId } : {}),
          },
          'fc-teugn-push',
        );
      return cachedApp;
    }

    return null;
  } catch {
    configurationFailed = true;
    return null;
  }
}

export function firebaseAdminApp(): App | null {
  return firebaseApp();
}

export function firebaseMessagingConfigured() {
  return externalDeliveriesAllowed && firebaseApp() !== null;
}

export function firebaseMessaging(): Messaging | null {
  if (!externalDeliveriesAllowed) return null;
  const app = firebaseApp();
  return app ? getMessaging(app) : null;
}
