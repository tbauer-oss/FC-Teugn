# Migration FC Teugn Talents: Vercel -> Firebase Hosting + Cloud Run

## Zielbild

- Flutter Web: Firebase Hosting
- API: Google Cloud Run in `europe-west3`
- `/api/**`: Firebase Hosting Rewrite auf Cloud Run
- Private Dateien: Google Cloud Storage
- Secrets: Google Secret Manager
- Erinnerungsjob: Google Cloud Scheduler
- PostgreSQL/Prisma: bestehende Datenbank bleibt zunächst unverändert

## Sicherheitsprinzip

Die produktive Vercel-Umgebung bleibt bis zum vollständig erfolgreichen Paralleltest aktiv. Kein Schritt in dieser Anleitung setzt voraus, dass Vercel vorher abgeschaltet wird.

## Phase 1 - Google-Projekt vorbereiten

1. Firebase-/Google-Cloud-Projekt festlegen.
2. APIs aktivieren: Cloud Run, Artifact Registry, Secret Manager, Cloud Scheduler, Cloud Storage, IAM Credentials.
3. Artifact Registry Repository `fc-teugn` in `europe-west3` anlegen.
4. Privaten Storage-Bucket anlegen.
5. Cloud-Run-Service-Account mit minimal erforderlichen Rollen anlegen.
6. GitHub Workload Identity Federation einrichten.
7. GitHub Repository Variables setzen:
   - `GCP_PROJECT_ID`
   - `GCP_WORKLOAD_IDENTITY_PROVIDER`
   - `GCP_SERVICE_ACCOUNT`
   - `GCS_BUCKET`

## Phase 2 - Secrets und Backend parallel vorbereiten

1. Workflow `migrate_vercel_env_to_gcp_secrets.yml` ausführen.
2. Vor Deployment prüfen, dass mindestens vorhanden sind:
   - `DATABASE_URL`
   - `ACCESS_TOKEN_SECRET`
   - `REFRESH_TOKEN_SECRET`
   - `EMERGENCY_ACCESS_SECRET`
   - `RESEND_API_KEY`
   - `VAPID_PUBLIC_KEY`
   - `VAPID_PRIVATE_KEY`
   - `CRON_SECRET`
3. `deploy_backend_cloud_run.yml` manuell ausführen.
4. Cloud-Run-Healthcheck prüfen.
5. Bestehende Vercel-API bleibt weiterhin produktiv.

## Phase 3 - Private Dateien migrieren

1. `migrate_vercel_blobs_to_gcs.yml` zuerst im Dry-Run ausführen.
2. Anzahl und Pfade der gefundenen Blobs gegen die Datenbankeinträge prüfen.
3. Migration ohne Löschung bei Vercel ausführen.
4. Stichproben prüfen:
   - Spielerfotos
   - Spielgemeinschafts-/Teamlogos
   - Gegnerlogos
   - Spielerdokumente
   - Support-Anhänge
   - Messenger-/Familienkontakt-Anhänge
5. Erst nach erfolgreichem Test Cloud Run mit `OBJECT_STORAGE_PROVIDER=gcs` verwenden.

## Phase 4 - Firebase Hosting parallel testen

1. `deploy_flutter_web_firebase.yml` manuell ausführen.
2. Firebase-Standarddomain testen, bevor die eigene Domain geändert wird.
3. Mindestens folgende Funktionen prüfen:
   - Login / Session Refresh / Logout
   - Dashboard
   - Spieler und Kader
   - Trainings und Spiele
   - Zu-/Absagen
   - Push-Registrierung
   - Push-Versand
   - Dokument-Upload und Download
   - Spielerfoto-Upload
   - Team-/Gegnerlogo
   - Live-Ticker
   - Erinnerungen
   - Passwort-Reset
   - BFV-/Wettbewerbsimport
   - Turniere
   - Registrierungsfreigabe
   - Rechte und Rollen
4. Browser-Netzwerk prüfen: API-Aufrufe müssen über `/api/...` laufen.

## Phase 5 - Scheduler

1. `configure_cloud_scheduler.yml` ausführen.
2. Scheduler zunächst pausiert lassen.
3. Manuell einen authentifizierten Aufruf auf `/internal/cron/reminders` durchführen.
4. Prüfen, dass keine doppelten Benachrichtigungen entstehen.
5. Erst beim Cutover den Google-Scheduler aktivieren und den Vercel-Cron deaktivieren.

## Phase 6 - Cutover

Cutover nur durchführen, wenn Backend-, Container-, Flutter- und Funktionstests grün sind.

1. Schreibende Funktionen kurz kontrolliert beobachten.
2. Letzten Blob-Synchronisationslauf durchführen.
3. Google Cloud Scheduler aktivieren.
4. Vercel Cron deaktivieren.
5. `app.fc-teugn-talents.de` auf Firebase Hosting umschalten.
6. SSL-/DNS-Status prüfen.
7. Login und kritische Schreibvorgänge erneut produktiv testen.
8. Runtime-Logs von Cloud Run beobachten.
9. Vercel Backend und Web mindestens mehrere Tage als Rollback-Option bestehen lassen.

## Rollback

Bei schwerwiegendem Fehler nach dem Domain-Cutover:

1. Google Cloud Scheduler sofort pausieren.
2. Vercel Cron wieder aktivieren.
3. Domain/DNS auf die vorherige Vercel-Konfiguration zurückstellen.
4. Keine GCS-Dateien löschen.
5. Vercel Blob nicht löschen.
6. Datenbank nicht zurückrollen, sofern keine Schema-Inkompatibilität entstanden ist.
7. Ursache auf dem Migrationsbranch beheben und Paralleltest wiederholen.

## Vercel endgültig entfernen

Erst wenn der neue Betrieb stabil bestätigt ist:

1. Prüfen, ob keine produktiven Requests mehr bei Vercel ankommen.
2. Prüfen, ob keine benötigten Dateien ausschließlich in Vercel Blob liegen.
3. Vercel-Cron dauerhaft entfernen.
4. Vercel-Deploy-Workflows aus GitHub entfernen.
5. `@vercel/blob` und verbliebene Vercel-spezifische Laufzeitabhängigkeiten entfernen.
6. Alte Vercel-Projekte deaktivieren/löschen.
7. Erst danach den kostenpflichtigen Vercel-Tarif kündigen.

## Abbruchkriterien vor Cutover

Kein Cutover bei:

- fehlgeschlagener CI
- fehlgeschlagenem Cloud-Run-Container-Build
- nicht migrierten privaten Dateien
- fehlenden Secrets
- nicht getesteten Push-/Reminder-Abläufen
- Fehlern bei Login/Token-Refresh
- fehlerhaftem Dokument-/Fotozugriff
- ungeklärten Prisma-/Datenbankproblemen
- nicht funktionsfähigem Rollback-Pfad
