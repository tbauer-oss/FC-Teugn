# Professioneller Vereinskalender

Der Kalender baut das bestehende `Event`-Modell additiv aus. Vorhandene
Termine, Spiele, Aufstellungen und Rückmeldungen bleiben erhalten.

## Funktionsumfang

- 15 fachliche Kategorien von Training über Pflicht- und Freundschaftsspiel
  bis Elternabend, Vereinsveranstaltung und Fototermin
- Tages-, Wochen-, Monats- und Agendaansicht
- Filter nach Mannschaft und Kategorie
- Termine für eine oder mehrere Mannschaften
- Treffpunkt, Adresse, Kartenlink, Heim/Auswärts, Gegner, Spielstätte,
  Ansprechpartner, Ausrüstung, Kleidung und Verpflegung
- maximale Teilnehmerzahl, Rückmeldefrist, Sichtbarkeit, Erinnerungszeitpunkte,
  Anhänge und interne Trainernotiz
- wöchentliche, zweiwöchentliche und frei nach Wochentagen konfigurierte Serien
- Änderung oder Absage eines einzelnen Vorkommnisses beziehungsweise aller
  folgenden Termine einer Serie
- Verbindliche Zusage, Absage mit optionalem Grund und offene Rückmeldung
- getrennte Speicherung von geplanter Teilnahme und tatsächlicher Anwesenheit
- Trainerübersicht mit Summen, offenen Rückmeldungen und
  Torhüterverfügbarkeit
- interne Erinnerungen an Spieler und kommunikationsberechtigte Eltern
- Fahrangebote, freie Plätze, Abfahrtsort/-zeit, Mitfahranfragen und
  Bestätigung durch Fahrer oder Trainer
- persönliches, widerrufbares ICS-Kalenderabonnement

## Daten- und Zugriffsschutz

Der API-Server berechnet die zugänglichen Mannschaften aus freigegebenen
`TeamMembership`-Datensätzen. Vereinsleitung sieht den aktiven Verein,
Trainer und Betreuer nur ihre zugeordneten Mannschaften. Eltern sehen
Rückmeldungen ausschließlich für verknüpfte Kinder, Spieler ausschließlich
das eigene Profil.

`STAFF_ONLY`-Termine und interne Trainernotizen werden nicht nur in Flutter
ausgeblendet, sondern serverseitig aus nicht berechtigten Antworten entfernt.
Telefonnummern von Fahrern werden nur dem Fahrer, berechtigten Trainern oder
Personen mit beteiligtem Kind übermittelt.

ICS-Abonnements verwenden einen zufälligen 192-Bit-Schlüssel. Ein erneutes
Erstellen rotiert den Schlüssel und macht die vorherige Adresse ungültig.
Im Feed werden keine internen Notizen, Teilnehmerdaten oder Telefonnummern
ausgegeben.

## Serientermine

Eine Serie wird in `EventSeries` beschrieben. Ihre Vorkommnisse werden als
normale `Event`-Datensätze materialisiert. Das ermöglicht performante
Kalenderabfragen und echte Einzelabweichungen. Bei einer Einzeländerung wird
`isSeriesException` gesetzt. Serienänderungen erfassen nur das ausgewählte und
zukünftige, noch nicht abweichende Vorkommnisse. Pro Serie werden höchstens
120 Vorkommnisse und maximal zwei Jahre erzeugt.

## Migration

`20260728210000_add_professional_calendar`:

- ergänzt ausschließlich neue Enum-Typen, Spalten, Indizes und Tabellen;
- ordnet bestehende Trainings- und Spieltermine automatisch passenden
  Kategorien zu;
- erstellt für jeden vorhandenen Termin einen `EventTargetTeam`-Datensatz;
- löscht oder überschreibt keine bestehenden Termine oder Rückmeldungen.

## API-Überblick

- `GET /events` – gefilterter, rollenabhängiger Kalender
- `POST /events` – Einzel- oder Serientermin
- `PUT /events/:id?scope=single|series` – Einzel-/Serienänderung
- `DELETE /events/:id?scope=single|series` – nachvollziehbare Absage
- `POST /events/:id/attendance` – Rückmeldung
- `PUT /events/:id/attendance/actual` – tatsächliche Anwesenheit
- `POST /events/:id/attendance/reminders` – offene Rückmeldungen erinnern
- `POST /events/:id/carpool-offers` – Fahrt anbieten
- `POST /events/:id/carpool-offers/:offerId/passengers` – Platz anfragen
- `PATCH /events/:id/carpool-offers/:offerId/passengers/:passengerId` –
  Anfrage bestätigen, ablehnen oder stornieren
- `POST /events/calendar-subscription` – persönlichen Schlüssel rotieren
- `GET /events/subscription/:token.ics` – abonnierbarer ICS-Feed

Alle schreibenden Verwaltungsaktionen werden über `MANAGE_EVENTS` geschützt.
Terminänderungen, Absagen und Erinnerungen erzeugen Audit-Log-Einträge.
