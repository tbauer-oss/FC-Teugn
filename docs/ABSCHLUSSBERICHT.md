# Abschlussbericht: professioneller Ausbau der FC-Teugn-App

Stand: 29. Juli 2026

## 1. Analysierter Ausgangszustand

Das vorhandene Repository bestand aus einer Flutter-App für Web und Android
sowie einem Express-/TypeScript-Backend mit Prisma und PostgreSQL. Die erste
Version hatte eine flache Mannschaftsstruktur, drei grobe Rollen, wenige
automatisierte Tests und mehrere noch nicht produktionsfähige Deployment- und
Registrierungsstellen. Die bestehende Anwendung wurde weiterentwickelt; es
wurde keine zweite Demo-App angelegt.

## 2. Implementierte Funktionen

- Vereinsstruktur `Verein > Saison > Altersklasse > Mannschaft`, mehrere
  Mannschaften je Jugend und Mehrfachzuordnungen je Benutzer
- erweiterte Rollen, zentrale Berechtigungsmatrix, Mannschaftsgrenzen und
  unveränderliche Audit-Historie
- professioneller Registrierungs- und Freigabeprozess mit versionierten
  Datenschutz- und Nutzungsbedingungen
- responsive, rollenabhängige Flutter-Navigation und Dashboards
- Mannschaftsprofile mit Jahrgängen, Trainingszeiten, Spielstätte,
  Verantwortlichen, BFV-/DFBnet-Referenzen und geschützten Fotos
- Spielerprofile, Eltern-Kind-Beziehungen, Entwicklungsnotizen, medizinische
  Notfallinformationen, Einwilligungen und private Dokumente
- Kalender mit Kategorien, Serien, Abweichungen, Rückmeldungen,
  Fahrgemeinschaften, Erinnerungen und ICS-Abonnement
- Spielverwaltung, Kadernominierung, grafische Aufstellung und
  Veröffentlichungszustände
- mobil optimierter Liveticker mit serverbasierter Uhr, Sequenzen,
  Idempotenz, Undo/Korrektur, Drei-Sekunden-Polling und persistenter
  Offline-Warteschlange
- automatisch abgeleitete Mannschafts- und Spielerstatistiken
- Trainingsbibliothek und Trainingspläne
- Mannschaftsmitteilungen, Lesebestätigungen, In-App-Benachrichtigungen,
  Präferenzen und Web-Push-Basis
- CSV-/ICS-Spielplanimport mit Vorschau, Prüfsummen, Duplikat- und
  Konfliktschutz
- versionierte Jugendregelprofile und transaktionssicherer Saisonwechsel mit
  Vorschau
- Aufgaben, Materialverwaltung, Checklisten und geschützte Notfallansicht
- sichere Access-/Refresh-Token-Rotation, Widerruf, Rate Limits und
  Datenschutz-Self-Service mit Export und kontrollierter Anonymisierung
- OpenAPI-3.1-Vertrag unter `GET /openapi.json`

## 3. Geänderte Bereiche

Die Umsetzung wurde in den Pull Requests 57 bis 74 veröffentlicht. Die
wesentlichen Bereiche sind:

- `api/prisma/schema.prisma` und `api/prisma/migrations/`
- `api/src/controllers/`, `api/src/routes/`, `api/src/services/`,
  `api/src/security/` und `api/src/middleware/`
- `fc_teugn_app/lib/core/` und `fc_teugn_app/lib/features/`
- `api/tests/`, `api/scripts/e2e-smoke.mjs` und `fc_teugn_app/test/`
- `.github/workflows/`, `vercel.json`, `api/vercel.json` und
  `fc_teugn_app/android/`
- `docs/`, `README.md` und die jeweiligen `.env.example`-Dateien

## 4. Datenbank und Migrationen

Es liegen 15 aufeinander aufbauende Prisma-Migrationen vor. Sie führen unter
anderem Verein, Saison, Altersgruppen, Memberships, Spielerfachdaten,
Kalender, Spieltag, Ticker, Statistik, Training, Kommunikation, Importe,
Regelprofile, Saisonwechsel, Registrierung, private Dateien, Refresh-Sitzungen,
Teamorganisation, Mannschaftsprofile und Betroffenenrechte ein.

GitHub Actions spielt bei jeder Abnahme alle Migrationen auf eine leere
PostgreSQL-16-Datenbank und anschließend die vollständig fiktiven Seed-Daten
ein. Dadurch werden sowohl Neuinstallation als auch Migrationsreihenfolge
automatisiert geprüft.

## 5. API

Die API ist fachlich in Authentifizierung, Administration, Organisation,
Spieler, Termine, Spiele, Statistik, Training, Kommunikation,
Benachrichtigungen, Importe und Mannschaftsorganisation getrennt. Kritische
Routen verwenden Authentifizierungs-, Freigabe-, Berechtigungs- und
Mannschaftsprüfungen. Der vollständige maschinenlesbare Vertrag liegt in
`api/openapi.json`.

## 6. Rollen und Berechtigungen

Unterstützt werden `SUPER_ADMIN`, `CLUB_ADMIN`, `YOUTH_DIRECTOR`, `COACH`,
`ASSISTANT_COACH`, `TEAM_MANAGER`, `PARENT`, `PLAYER` und `READ_ONLY`.
Historische Rollenbezeichnungen bleiben migrationsverträglich.

Die Berechtigungen umfassen Organisation, Mannschaft, Mitglieder, Spieler,
sensible Spielerdaten, Dokumente, Entwicklung, Termine, Aufstellungen,
Liveticker, Statistik, Training, Mitteilungen, Importe, Rückmeldungen und
Teamorganisation. Die Durchsetzung erfolgt im Backend; die Oberfläche nutzt
dieselben Rechte nur ergänzend zur Darstellung.

## 7. Ausgeführte Tests

- 27 Backend-Fach-, Sicherheits- und Vertragstests
- Prisma-Validierung und vollständiger Migrationslauf auf PostgreSQL 16
- vollständige mutierende HTTP-E2E-Kette:
  Registrierung, Freigabe, Eltern-Kind-Zuordnung, Training, Zusage,
  Anwesenheit, Spiel, Kader, Aufstellung, Liveticker, zwei unabhängige
  Eltern-Sitzungen, Korrektur, Spielende und Statistik
- Flutter-Formatierung, statische Analyse und Widget-/Modelltests
- Web-Release-Build
- signierter Android-App-Bundle-Build mit temporärem CI-Schlüssel

## 8. Build- und Produktionsstatus

GitHub Actions ist für Backend und Flutter grün. Frontend und Backend werden
automatisch nach Vercel ausgerollt. Produktiv geprüft wurden:

- `https://fc-teugn.vercel.app` mit HTTP 200
- `https://fc-teugn-backend.vercel.app` mit `{"status":"ok"}`
- OpenAPI 3.1 mit HTTP 200
- anonymer Datenschutzexport mit HTTP 401
- Registrierungs-Preflight mit korrekter CORS-Origin und HTTP 204

## 9. Lokaler Start

```bash
cd api
npm install
npx prisma migrate deploy
npm run prisma:seed
npm run dev
```

In einem zweiten Terminal:

```bash
cd fc_teugn_app
flutter pub get
flutter run -d chrome
```

Der mutierende E2E-Test darf nur gegen eine entbehrliche Testdatenbank laufen:

```bash
cd api
npm run build
npm start
# zweites Terminal
npm run test:e2e
```

## 10. Umgebungsvariablen

Pflicht beziehungsweise produktiv relevant:

- `DATABASE_URL`
- `ACCESS_TOKEN_SECRET`
- `REFRESH_TOKEN_SECRET`
- `EMERGENCY_ACCESS_SECRET`
- `CORS_ORIGINS`
- `API_BASE_URL` beim Flutter-Build, sofern die Standarddomain abweicht
- `BLOB_READ_WRITE_TOKEN` für private Spieler- und Mannschaftsdateien

Für Web Push:

- `VAPID_PUBLIC_KEY`
- `VAPID_PRIVATE_KEY`
- `VAPID_SUBJECT`

## 11. Noch erforderliche externe Zugangsdaten

- Ein dauerhaftes Android-Release-Keystore und Google-Play-Zugang werden erst
  für eine Store-Veröffentlichung benötigt. Die Buildkonfiguration ist in
  `fc_teugn_app/android/app/build.gradle.kts` und `docs/android-release.md`
  vorbereitet.
- Native Android-Push-Auslieferung benötigt ein Firebase-Projekt samt
  Zugangsdaten. Datenmodell, Präferenzen und Web Push sind in
  `api/src/services/notification.service.ts` sowie der Flutter-App vorbereitet.
- Ein offizieller BFV-/SpielPLUS-Connector benötigt eine dokumentierte,
  freigegebene Schnittstelle und rechtmäßige Zugangsdaten.

## 12. BFV-/SpielPLUS-Stand

Produktiv vorhanden sind manuelle Referenzen, CSV- und ICS-Import,
Providerabstraktion, Prüfsummen, Vorschau, Konfliktanzeige und
Duplikatvermeidung. Es werden weder Scraping noch private oder erfundene
Endpunkte eingesetzt. Ein offizieller Connector wird erst ergänzt, wenn der
BFV eine freigegebene Schnittstelle und Zugangsdaten bereitstellt. Vorbereitet
ist dies in `api/src/services/competition-provider.ts`.

## 13. Bekannte Restpunkte

### Native Android-Push-Nachrichten

Offen, weil Firebase-Projekt und Produktionszugangsdaten außerhalb des
Repositories fehlen. Benachrichtigungsmodell, Kategorien, Präferenzen und
Web-Push-Auslieferung sind vorhanden. Nächster Schritt: Firebase-Projekt
anlegen, Android-App registrieren, Schlüssel sicher in Vercel/GitHub
hinterlegen und einen realen Gerätetest durchführen.

### Offizieller BFV-/SpielPLUS-Connector

Offen, weil keine nachgewiesene öffentliche Schnittstelle freigegeben wurde.
CSV-/ICS-Provider und Konfliktlogik sind bereits produktiv. Nächster Schritt:
offizielle Schnittstellendokumentation und Nutzungsfreigabe beschaffen und
einen weiteren Provider hinter der bestehenden Abstraktion implementieren.

### Minutengenaue zeitgesteuerte Veröffentlichung ohne App-Aufruf

Fällige Mitteilungen werden derzeit atomar beim Abruf verarbeitet. Ein
serverseitiger Prozessor ist vorhanden; für minutengenaue Ausführung ohne
Benutzeraktivität fehlt nur ein Vercel-Cron-Aufruf. Nächster Schritt:
geschützten Cron-Endpunkt konfigurieren und in Vercel zeitlich planen.

### Optionale Mannschaftskasse

Dieses ausdrücklich optionale Modul wurde nicht aktiviert, weil keine
Zahlungs- oder Kassenanforderungen vorgegeben wurden. Aufgaben, Material und
Checklisten sind produktiv. Vor einer Kassenfunktion müssen
Berechtigungskonzept, Aufbewahrung, Exportformat und vereinsrechtliche
Verantwortung festgelegt werden; eine Zahlungsdienstintegration ist nicht
enthalten.

