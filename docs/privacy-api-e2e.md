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

Der read-only E2E-Smoke-Test läuft gegen eine gestartete, mit Seed-Daten
befüllte Umgebung:

```bash
cd api
npm run prisma:seed
npm run dev
# zweites Terminal
npm run test:e2e
```

Abweichende Umgebungen können `E2E_BASE_URL`, `E2E_TRAINER_EMAIL`,
`E2E_PARENT_EMAIL` und `E2E_PASSWORD` setzen. Der Test verändert keine Termine
oder Spieldaten. Er prüft echte HTTP-Aufrufe für Anmeldung, Rollengrenzen,
Organisation, Termine, Spiele und personenbezogenen Datenexport.
