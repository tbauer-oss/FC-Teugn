# FC-Teugn-App: Ist-Analyse und Zielarchitektur

Stand: 28. Juli 2026

## Ausgangslage

Das Repository enthält eine gemeinsam deployte Produktbasis:

- Flutter mit Riverpod, Dio, go_router und Material 3
- Express/TypeScript mit Prisma, PostgreSQL, JWT und bcrypt
- getrennte Vercel-Projekte für Flutter-Web und API
- GitHub-Actions-Deployments für Frontend und Backend

Registrierung, Login, Freigaben, Spieler, Termine, Anwesenheiten und einfache
Spieldaten sind bereits Ende-zu-Ende angebunden. Die produktive Datenbank wird
über versionierte Prisma-Migrationen aktualisiert.

## Festgestellte Lücken

### Datenmodell

Das ursprüngliche Modell kannte nur eine flache `Team`-Entität. Verein,
Spielzeit und Altersklasse fehlten. Nutzer waren genau einem Team und einer von
drei Rollen zugeordnet. Saisonwechsel, mehrere Teams pro Altersklasse,
vereinsweite Administration und differenzierte Zugriffe waren damit nicht
abbildbar.

### Sicherheit

Routen prüften feste Rollenlisten. Eine zentrale, testbare Berechtigungsmatrix,
Team-Mitgliedschaften und ein Audit-Protokoll fehlten. Die Zugriffe waren zwar
auf die `teamId` aus dem Token begrenzt, aber noch nicht für mehrere
Mannschaften eines Nutzers ausgelegt.

### API

Vorhanden waren Auth-, Admin-, Spieler- und Terminrouten. Es fehlten ein
Organisationskontext, konsistente Vereinsstammdaten, Teamverwaltung,
Pagination/DTO-Validierung und eine OpenAPI-Beschreibung.

### Flutter-App

Die App besitzt bereits getrennte Trainer- und Elternbereiche sowie eine
responsive Navigation. Viele Seiten sind jedoch noch einfache Listen/Dialoge.
Es fehlen Vereinskontext, Saison-/Teamwechsel, einheitliche Detailseiten,
granulare rollenbasierte Aktionen, Offline-Zustände und die umfangreichen
Fachmodule aus dem Masterauftrag.

### Qualität

Es existierte nur ein Flutter-Smoke-Test. Backend-Unit-/Integrationstests,
API-Vertragstests, Migrationsproben und fachliche End-to-End-Szenarien müssen
systematisch ergänzt werden.

## Zielarchitektur

Die vorhandene Anwendung wird ohne parallele Demo weiterentwickelt:

```text
Club
└── Season
    └── AgeGroup (G bis A)
        └── Team (beliebig viele)
            ├── TeamMembership
            ├── Player
            ├── Event / Attendance
            ├── Match / Squad / LiveTicker
            └── Communication / Tasks / Documents
```

Serverseitige Zugriffe werden künftig über zentrale Permissions und
Team-Mitgliedschaften entschieden. Sensible Kinder-, Medizin- und
Einwilligungsdaten erhalten getrennte Berechtigungen und Audit-Einträge.
Flutter liest einen gemeinsamen Organisationskontext und zeigt Navigation,
Aktionen und Dashboards rollenabhängig an.

## Umsetzungsreihenfolge

1. Vereinsstruktur, Rollen, Permissions, Memberships, Audit und sichere
   Migration
2. Responsives App-Shell, Organisationsseite, moderne Dashboards und
   einheitliche UI-Bausteine
3. Registrierung/Freigabecenter und professionelle Spielerprofile
4. Kalender, Serien, Zusagen, Fahrgemeinschaften und ICS
5. Spieltag, Kader/Aufstellung, Live-Ticker und Statistik
6. Trainingsplanung, Kommunikation, Dokumente, Aufgaben und optionale Kasse
7. BFV-Importe über dokumentierte CSV-/ICS-/Provider-Schnittstellen
8. Offline-Queue, Push, Datenschutzwerkzeuge, umfassende Tests und OpenAPI

Jede Stufe wird als lauffähiger vertikaler Schnitt mit Migration, API,
Flutter-Oberfläche, Tests, Dokumentation und Deployment ausgeliefert.

## Fortschreibung

Die geplanten vertikalen Produktschnitte sind inzwischen umgesetzt. Dazu
gehören die persistente Liveticker-Offline-Warteschlange, vollständige
Mannschaftsstammdaten, Datenschutz-Self-Service, OpenAPI-Vertragstests und
eine mutierende HTTP-End-to-End-Abnahme gegen eine isolierte
PostgreSQL-Datenbank. Web Push ist technisch angebunden; native
Android-Push-Auslieferung benötigt weiterhin ein externes Firebase-Projekt.
Der konsolidierte Lieferstand und alle externen Restvoraussetzungen sind in
[`ABSCHLUSSBERICHT.md`](ABSCHLUSSBERICHT.md) dokumentiert.
