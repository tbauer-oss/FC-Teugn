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

## Frontend (Flutter web)
- Source: [`fc_teugn_app/`](fc_teugn_app)
- Local dev: install Flutter 3.22+, then run `flutter pub get` and `flutter run -d chrome` from `fc_teugn_app`.
- Build: `flutter build web --release`.
- Android: Die produktive App-ID, Release-Signierung und der geprüfte
  App-Bundle-Build sind in
  [`docs/android-release.md`](docs/android-release.md) dokumentiert.
- Deployment: Vercel uses the root [`vercel.json`](vercel.json) to run `vercel_install.sh` / `vercel_build.sh` and publish the generated `fc_teugn_app/build/web` directory.
- Running Flutter without root warnings: use [`scripts/run_flutter_as_user.sh`](scripts/run_flutter_as_user.sh) to execute commands as an unprivileged user, e.g. `FLUTTER_USER=deployer ./scripts/run_flutter_as_user.sh pub outdated`.

## Backend (Express + Prisma)
- Source: [`api/`](api)
- Install: `npm install` then `npx prisma generate` (requires `DATABASE_URL`).
- Local dev: `npm run dev` (default port `4000`).
- Build: `npm run build` outputs to `api/dist`.
- Deployment: create a separate Vercel project with the root directory set to `api/`. The included `vercel.json` handles install/build and packages Prisma artifacts for the serverless function.
- Project linking: place your Vercel IDs into [`api/.vercel/project.json`](api/.vercel/project.json) (`projectId` = `prj_…`, `orgId` = `team_…`) so the CLI reuses the existing `fc-teugn-backend` project instead of creating a new one. Then set `VERCEL_TOKEN` and run [`api/scripts/vercel_link.sh`](api/scripts/vercel_link.sh). You can override the project slug via `VERCEL_PROJECT_SLUG` if needed.

## API/Frontend integration
The root `vercel.json` now preserves `/api/*` routes so the deployed frontend can call the backend on the same domain while still rewriting other paths to `index.html` for SPA routing.

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
