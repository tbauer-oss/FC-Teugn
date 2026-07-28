# Mitglieder- und Spielerprofile

Stand: 28. Juli 2026

## Freigabecenter

Das Freigabecenter trennt Registrierung und tatsächliche Berechtigung:

- neue Konten bleiben bis zur Prüfung im Status `PENDING`
- freigebende Personen wählen eine zulässige Rolle
- ein Mitglied kann mehreren Mannschaften zugeordnet werden
- für Spielerzugänge wird ein konkretes Spielerprofil verknüpft
- Blockierung, Rollen- und Teamzuordnung werden im Audit-Log protokolliert
- Trainer und Teamorganisation dürfen nur eingeschränkte Teamrollen vergeben;
  vereinsweite Rollen erfordern die Organisationsberechtigung

## Spielerprofil

Ein Spielerprofil enthält:

- Stammdaten, Rufname, Geburtsdatum, Nationalität und Eintrittsdatum
- Haupt-/Nebenposition, starker Fuß, Trikotnummer und Kaderstatus
- strukturierte Sorgeberechtigtenbeziehungen und Abholberechtigungen
- getrennt berechtigte Gesundheitsdaten und Notfallkontakte
- Entwicklungsbeobachtungen nach Kategorie, Bewertung und Sichtbarkeit
- widerrufbare Einwilligungen für Fotos, Mannschaftsfotos, Transport,
  Gesundheitsdaten und Kommunikation

Eltern sehen ausschließlich verknüpfte Kinder. Geteilte Entwicklungsnotizen
werden über `GUARDIANS_AND_STAFF` ausdrücklich freigegeben. Interne
Trainerbeobachtungen bleiben `STAFF_ONLY`. Spielerzugänge sehen nur das mit
ihrem Konto verknüpfte Profil.

## API

```text
GET    /admin/pending-users
GET    /admin/members
POST   /admin/approve
POST   /admin/assign-parent-player

GET    /players
GET    /players/:id
POST   /players
PUT    /players/:id
PUT    /players/:id/medical
POST   /players/:id/emergency-contacts
POST   /players/:id/development-notes
PUT    /players/:id/consents/:type
DELETE /players/:id
```

Alle Routen verwenden den authentifizierten Teamkontext. Sensible Daten
werden zusätzlich anhand von Permission und Sorgeberechtigtenbeziehung
gefiltert.
