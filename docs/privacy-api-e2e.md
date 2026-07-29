# Datenschutz-Self-Service, API-Vertrag und E2E-Abnahme

## Betroffenenrechte

Angemeldete Benutzer finden den Bereich **Datenschutz & Ihre Daten** in der
Desktop-Navigation beziehungsweise über das Schildsymbol auf Mobilgeräten.

- Der Datenexport liefert das eigene Konto und Daten verknüpfter Kinder nur bei
  hinterlegter gesetzlicher Vertretung als strukturiertes JSON.
- Jeder Export wird im Auditprotokoll vermerkt.
- Ein Löschantrag verlangt die exakte Sicherheitsbestätigung `KONTO LÖSCHEN`.
- Doppelte offene Löschanträge werden verhindert.
- Nur Vereinsadministration oder Jugendleitung kann einen Antrag bearbeiten.
- Der Abschluss widerruft alle Refresh Tokens, entfernt Push-Abos und aktive
  Team-/Elternzuordnungen, trennt ein eigenes Spielerprofil und ersetzt
  Identitäts- und Kontaktdaten irreversibel.
- Audit- und fachliche Vereinshistorie bleibt unter dem neutralen Namen
  „Gelöschtes Konto“ erhalten.

Die Anonymisierung ist bewusst keine sofortige Self-Service-Löschung. Vorher
müssen gesetzliche und vereinsrechtliche Aufbewahrungspflichten geprüft werden.

## OpenAPI

Der maschinenlesbare Vertrag liegt in `api/openapi.json` und wird im laufenden
Backend unter `GET /openapi.json` ausgeliefert. Er dokumentiert die zentralen
Produktionsabläufe, JWT-Sicherheit und standardisierte Fehlerantworten.

## Automatisierte Abnahme

`npm test` validiert neben den Fach- und Berechtigungstests auch:

- Vorhandensein der sicherheitskritischen OpenAPI-Pfade,
- JWT-Sicherheitsschema,
- vollständige Entfernung identifizierender Kontofelder bei Anonymisierung.

Der mutierende E2E-Abnahmetest läuft ausschließlich gegen eine gestartete,
mit fiktiven Seed-Daten befüllte Testumgebung:

```bash
cd api
npm run prisma:seed
npm run dev
# zweites Terminal
npm run test:e2e
```

Abweichende Testumgebungen können `E2E_BASE_URL`, `E2E_TRAINER_EMAIL`,
`E2E_PASSWORD`, `E2E_TEAM_ID` und `E2E_PLAYER_ID` setzen. Der Test erzeugt
bewusst Registrierungen, Termine, Spiele und Tickerereignisse und darf deshalb
nicht gegen die Produktivdatenbank ausgeführt werden.

GitHub Actions startet dafür einen isolierten PostgreSQL-16-Dienst, spielt alle
Prisma-Migrationen und Seed-Daten ein und prüft die vollständige Fachkette:

1. Elternregistrierung und ausstehender Status,
2. Adminfreigabe und Eltern-Kind-Zuordnung,
3. Training, Zusage und tatsächliche Anwesenheit,
4. Spiel, Kadernominierung und veröffentlichte Aufstellung,
5. Livetickerstart, Tore, Idempotenz und Korrektur,
6. identischer Live-Stand in zwei unabhängigen Eltern-Sitzungen,
7. Spielende und daraus neu berechnete Statistiken.

Zusätzlich stellt der Test sicher, dass interne taktische Notizen nicht an
Eltern ausgeliefert werden.
