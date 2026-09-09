# FC-Teugn

Full-stack project containing a Flutter web frontend (`fc_teugn_app`) and a Node/Express + Prisma backend (`api`).

The product is being expanded into a club-wide youth football platform. The
current architecture assessment and implementation order are documented in
[`docs/architecture-analysis.md`](docs/architecture-analysis.md).
The professional team master-data model and its protected photo handling are
documented in
[`docs/professional-team-profiles.md`](docs/professional-team-profiles.md).
Datenschutz-Self-Service, der veröffentlichte OpenAPI-Vertrag und die
Ende-zu-Ende-Abnahme sind unter
[`docs/privacy-api-e2e.md`](docs/privacy-api-e2e.md) beschrieben.
Der konsolidierte Lieferstand, die Buildnachweise und die verbleibenden
externen Voraussetzungen stehen im
[`docs/ABSCHLUSSBERICHT.md`](docs/ABSCHLUSSBERICHT.md).

## Frontend (Flutter web)
- Source: [`fc_teugn_app/`](fc_teugn_app)
- Local dev: install Flutter 3.22+, then run `flutter pub get` and `flutter run -d chrome` from `fc_teugn_app`.
- Build: `flutter build web --release`.
- Android: Die produktive App-ID, Release-Signierung und der geprüfte
  App-Bundle-Build sind in
  [`docs/android-release.md`](docs/android-release.md) dokumentiert.
- Deployment: Firebase Hosting publishes `fc_teugn_app/build/web` through `firebase.json`. The stable address is https://app.fc-teugn-talents.de.
- Running Flutter without root warnings: use [`scripts/run_flutter_as_user.sh`](scripts/run_flutter_as_user.sh) to execute commands as an unprivileged user, e.g. `FLUTTER_USER=deployer ./scripts/run_flutter_as_user.sh pub outdated`.

## Backend (Express + Prisma)
- Source: [`api/`](api)
- Install: `npm install` then `npx prisma generate` (requires `DATABASE_URL`).
- Local dev: `npm run dev` (default port `4000`).
- Build: `npm run build` outputs to `api/dist`.
- Deployment: Google Cloud Run uses `api/Dockerfile` in `europe-west3`.
- Private files and shared scheduler state: Google Cloud Storage through Firebase Admin and the Cloud Run service account. Set `OBJECT_STORAGE_BUCKET`.

## API/Frontend integration
Firebase Hosting forwards `/api` and `/api/**` to Cloud Run. The server accepts
both the preserved prefix and direct Cloud Run paths. PostgreSQL remains at
Neon, transactional email at Resend, Android updates at the existing club download.

## Release and transition
`ci.yml` validates code and produces the signed Android artifact.
`release_google.yml` validates the exact successful CI run and deploys Cloud Run,
then Firebase Hosting, then the Android manifest. Production release jobs cannot
be started directly without validation. See [Google cutover](docs/google-cutover.md).
Only `legacy-bridge/` is deployed at the old Vercel addresses. It contains routing
and static transition pages, without API functions, cron jobs or database code.
`@vercel/blob` is a development dependency solely for the one-time verification
and migration script; the production container prunes it.

## Environment variables
Common variables:
- `DATABASE_URL`: PostgreSQL connection string for Prisma.
- `ACCESS_TOKEN_SECRET` / `REFRESH_TOKEN_SECRET`: separate, long random secrets
  for access and refresh token signing (`JWT_SECRET` remains a compatibility
  alias for older installations).
- `EMERGENCY_ACCESS_SECRET`: optional independent signing secret for
  five-minute, event-scoped emergency access tokens. Set a long random value in
  production.
- `CORS_ORIGINS`: comma-separated origins allowed by the backend.
- `API_BASE_URL`: optional override for the frontend API base URL.

## Organization model

The production data model follows `Club > Season > AgeGroup > Team` and
supports all youth levels from G to A. Access is controlled by centralized
permissions and team memberships; administrative changes are written to an
audit log.

Member approval, multi-team assignments, guardian relationships, development
notes, medical details and revocable player consents are described in
[`docs/member-player-profiles.md`](docs/member-player-profiles.md).

Der professionelle Kalender mit Serienterminen, Rückmeldungen,
Fahrgemeinschaften und ICS-Abonnement ist in
[`docs/professional-calendar.md`](docs/professional-calendar.md) beschrieben.

Spieltagsplanung, Kadernominierung, grafische Aufstellung und Liveticker sind in
[`docs/matchday-lineup-live-ticker.md`](docs/matchday-lineup-live-ticker.md)
beschrieben.

Automatisch abgeleitete Statistiken, Datenschutzgrenzen und die professionelle
Trainingsplanung sind in
[`docs/statistics-training-planning.md`](docs/statistics-training-planning.md)
beschrieben.

Mannschaftsmitteilungen, Lesebestätigungen, persönliche
Benachrichtigungseinstellungen und die Web-Push-Basis sind in
[`docs/communications-notifications-push.md`](docs/communications-notifications-push.md)
beschrieben.

Der sichere Spielplanimport mit CSV-/ICS-Providerabstraktion,
Duplikatschutz und Konfliktvorschau ist in
[`docs/competition-imports.md`](docs/competition-imports.md) beschrieben.

Versionierte Regelprofile und der transaktionssichere, geführte Saisonwechsel
sind in
[`docs/SAISONWECHSEL-UND-REGELPROFILE.md`](docs/SAISONWECHSEL-UND-REGELPROFILE.md)
beschrieben.

Der mehrstufige Registrierungs- und Freigabeprozess mit versionierten
Einwilligungen ist in
[`docs/PROFESSIONELLE-REGISTRIERUNG.md`](docs/PROFESSIONELLE-REGISTRIERUNG.md)
beschrieben.

Teambezogene Aufgaben, Materialausgaben und wiederverwendbare Checklisten sind
in [`docs/team-operations.md`](docs/team-operations.md) beschrieben.

Die passwortgeschützte, terminbezogene Notfallansicht für berechtigte
Trainerrollen ist in
[`docs/emergency-access.md`](docs/emergency-access.md) beschrieben.

## Cleaning the workspace
A root `.gitignore` now excludes build artifacts and dependency directories (e.g., `node_modules`, `api/dist`, `fc_teugn_app/build`).
