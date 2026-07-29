const baseUrl = process.env.E2E_BASE_URL ?? 'http://localhost:4000';
const trainerEmail = process.env.E2E_TRAINER_EMAIL ?? 'trainer@fc-teugn.local';
const parentEmail = process.env.E2E_PARENT_EMAIL ?? 'eltern@fc-teugn.local';
const password = process.env.E2E_PASSWORD ?? 'FC-Teugn_WEB!';

async function request(path, options = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    ...options,
    headers: {
      'content-type': 'application/json',
      ...(options.headers ?? {}),
    },
  });
  const body = response.status === 204
    ? null
    : await response.json().catch(() => null);
  if (!response.ok) {
    throw new Error(`${options.method ?? 'GET'} ${path}: ${response.status} ${JSON.stringify(body)}`);
  }
  return body;
}

async function login(email) {
  const session = await request('/auth/login', {
    method: 'POST',
    body: JSON.stringify({ email, password }),
  });
  return session.accessToken;
}

console.log(`E2E read-only smoke against ${baseUrl}`);
const status = await request('/');
if (status.status !== 'ok') throw new Error('API status is not ok');
const contract = await request('/openapi.json');
if (contract.openapi !== '3.1.0') throw new Error('OpenAPI contract missing');

const [trainerToken, parentToken] = await Promise.all([
  login(trainerEmail),
  login(parentEmail),
]);
const auth = (token) => ({ authorization: `Bearer ${token}` });

const [trainerContext, parentContext, events, matches, exportData] = await Promise.all([
  request('/organization/context', { headers: auth(trainerToken) }),
  request('/organization/context', { headers: auth(parentToken) }),
  request('/events', { headers: auth(trainerToken) }),
  request('/matches', { headers: auth(trainerToken) }),
  request('/auth/privacy/export', { headers: auth(parentToken) }),
]);

if (!trainerContext.permissions.includes('MANAGE_EVENTS')) {
  throw new Error('Trainer lacks MANAGE_EVENTS');
}
if (parentContext.permissions.includes('MANAGE_EVENTS')) {
  throw new Error('Parent unexpectedly has MANAGE_EVENTS');
}
if (!Array.isArray(events) || !Array.isArray(matches)) {
  throw new Error('Event or match collections are invalid');
}
if (exportData.user.email !== parentEmail) {
  throw new Error('Privacy export does not belong to the authenticated parent');
}

console.log('E2E smoke passed: auth, role boundaries, organization, events, matches, privacy export');
