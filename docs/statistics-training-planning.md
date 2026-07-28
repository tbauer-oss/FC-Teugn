# Automatische Statistiken und Trainingsplanung

## Statistiken

Spieler- und Mannschaftswerte werden aus gespeicherten Spielen, veröffentlichten
Aufstellungen, tatsächlicher Anwesenheit und nicht widerrufenen
Livetickerereignissen abgeleitet.

Die Neuberechnung erfolgt automatisch nach Toren, Tickerkorrekturen und
Spielende. Berechtigte Trainer können ein einzelnes Spiel zusätzlich manuell neu
berechnen.

Erfasst werden unter anderem:

- Einsätze und Startelfeinsätze
- Spielminuten
- Tore und Vorlagen
- Torwart- und Kapitänskennzeichnung
- Siege, Unentschieden, Niederlagen und Siegquote
- Tore je Spiel, Form sowie Heim-/Auswärtsbilanz

Eltern sehen ausschließlich Werte zugeordneten Kinder; Spieler ausschließlich
das eigene Profil. Es wird keine öffentliche Leistungsrangliste für
Minderjährige bereitgestellt.

```text
GET  /statistics
POST /statistics/matches/:matchId/recalculate
```

## Trainingsplanung

Trainingstermine bleiben Kalendertermine vom Typ `TRAINING` und erhalten einen
optionalen strukturierten `TrainingPlan`.

Ein Plan enthält:

- Schwerpunkte und Lernziele
- Trainer, Material und Platzaufteilung
- geordnete Phasen: Aufwärmen, Hauptteil, Spielform und Abschluss
- freie Bausteine oder Verknüpfungen mit der Übungsbibliothek
- Feedback nach der Einheit

Die Übungsbibliothek ist mannschaftsbezogen und speichert Aufbau, Ablauf,
Coachingpunkte, Varianten, Dauer, Spielerzahl und Material.

Die tatsächliche Anwesenheit ist von der vorherigen Terminrückmeldung getrennt.
Unterstützt werden anwesend, entschuldigt, unentschuldigt, verletzt, verspätet
und früher gegangen.

```text
GET    /trainings
GET    /trainings/:id
PUT    /trainings/:id/plan
PUT    /trainings/:id/attendance
GET    /trainings/exercises
POST   /trainings/exercises
PUT    /trainings/exercises/:exerciseId
DELETE /trainings/exercises/:exerciseId
```
