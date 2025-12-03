# FC-Teugn

Full-stack project containing a Flutter web frontend (`fc_teugn_app`) and a Node/Express + Prisma backend (`api`).

## Frontend (Flutter web)
- Source: [`fc_teugn_app/`](fc_teugn_app)
- Local dev: install Flutter 3.22+, then run `flutter pub get` and `flutter run -d chrome` from `fc_teugn_app`.
- Build: `flutter build web --release`.
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
- `JWT_SECRET` / `REFRESH_TOKEN_SECRET`: secrets for access/refresh token signing.
- `CORS_ORIGINS`: comma-separated origins allowed by the backend.
- `API_BASE_URL`: optional override for the frontend API base URL.

## Cleaning the workspace
A root `.gitignore` now excludes build artifacts and dependency directories (e.g., `node_modules`, `api/dist`, `fc_teugn_app/build`).
