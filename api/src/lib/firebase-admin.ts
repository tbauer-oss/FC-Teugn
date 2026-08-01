import { App, cert, getApps, initializeApp } from 'firebase-admin/app';
import { Messaging, getMessaging } from 'firebase-admin/messaging';

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

function firebaseApp(): App | null {
  if (cachedApp) return cachedApp;
  if (configurationFailed) return null;
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
  if (!raw) return null;
  try {
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
  } catch {
    configurationFailed = true;
    return null;
  }
}

export function firebaseMessagingConfigured() {
  return firebaseApp() !== null;
}

export function firebaseMessaging(): Messaging | null {
  const app = firebaseApp();
  return app ? getMessaging(app) : null;
}
