# Isolierte Testumgebung

Die Testumgebung ist bewusst **kein Mandant in der Produktivdatenbank**. Sie
besteht aus einem eigenen Vercel-Backend, einem eigenen Vercel-Frontend und
einer eigenen PostgreSQL-/Neon-Datenbank.

## Technische Schutzgrenzen

- `APP_ENVIRONMENT=demo` akzeptiert ausschließlich `DEMO_DATABASE_URL` und
  fällt nie auf `DATABASE_URL` zurück.
- Der Demo-Seed startet nur mit einem ausdrücklich gesetzten
  `DEMO_SEED_PASSWORD`; ein bekanntes Standardkennwort ist ausgeschlossen.
- Firebase-, Web-Push- und E-Mail-Zustellung sind im Demo-Backend immer
  deaktiviert. In-App-Mitteilungen können weiterhin funktional getestet werden.
- Das Demo-Frontend wird mit eigener API-Adresse gebaut und zeigt dauerhaft
  den Streifen `TESTUMGEBUNG · KEINE PRODUKTIVDATEN`.
- Der Demo-Workflow läuft ausschließlich manuell und prüft, dass weder das
  produktive Backend-Projekt noch die produktive API-Adresse verwendet werden.

## Einmalige externe Einrichtung

1. Eine leere, eigenständige Neon-Datenbank bzw. ein isoliertes Neon-Projekt
   anlegen. Keine produktive Branch-Datenbank und keinen produktiven
   Connection String verwenden.
2. Zwei neue Vercel-Projekte anlegen, zum Beispiel
   `fc-teugn-backend-demo` und `fc-teugn-demo`.
3. Im Demo-Backend-Projekt mindestens folgende Production-Variablen setzen:
   - `APP_ENVIRONMENT=demo`
   - `DEMO_DATABASE_URL=<Connection String der Demo-Datenbank>`
   - `ACCESS_TOKEN_SECRET=<eigenes Demo-Secret, mindestens 32 Zeichen>`
   - `REFRESH_TOKEN_SECRET=<zweites Demo-Secret, mindestens 32 Zeichen>`
   - `EMERGENCY_ACCESS_SECRET=<eigenes Demo-Secret, mindestens 32 Zeichen>`
   - `PUBLIC_APP_URL=<URL des Demo-Frontends>`
   - `CORS_ORIGINS=<URL des Demo-Frontends>`
   - `CRON_SECRET=<eigenes Demo-Secret>`
4. Im Demo-Backend ausdrücklich **keine** produktiven Werte für Firebase,
   VAPID, Resend oder Blob Storage hinterlegen.
5. Im GitHub-Repository konfigurieren:
   - Secret `DEMO_DATABASE_URL`
   - Secret `DEMO_SEED_PASSWORD`
   - Variable `DEMO_API_BASE_URL`
   - Variable `DEMO_BACKEND_VERCEL_PROJECT`
   - Variable `DEMO_FRONTEND_VERCEL_PROJECT`
6. GitHub Action `Deploy isolated demo environment` manuell starten.

Der vorhandene Seed erzeugt ausschließlich fiktive Beispielkonten und
-termine in der Demo-Datenbank. Das Kennwort dieser Konten entspricht dem nur
für die Demo hinterlegten Secret `DEMO_SEED_PASSWORD`.
