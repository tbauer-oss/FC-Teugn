# Team-Organisation

Das Modul bündelt wiederkehrende organisatorische Arbeit einer
Jugendmannschaft. Alle Datensätze sind einer Mannschaft zugeordnet und werden
im Backend gegen die tatsächlich freigegebenen Teamzuordnungen geprüft.

## Aufgaben

Trainer und Betreuer können Aufgaben wie Trikotwäsche, Fahrdienst,
Turnierdienst, Verpflegung oder Auf- und Abbau anlegen. Eine Aufgabe enthält
Verantwortlichen, Frist, optionale Erinnerung, Beschreibung und einen der
Statuswerte `OPEN`, `IN_PROGRESS`, `DONE` oder `CANCELLED`.

Eltern und Spieler dürfen den Bereich lesen, erhalten über die API jedoch nur
Aufgaben, die ihnen zugewiesen wurden oder die sie selbst angelegt haben.
Änderungen benötigen `MANAGE_TEAM_OPERATIONS`.

## Material

Materialpositionen besitzen Kategorie, Gesamtbestand, Betriebsstatus und eine
Ausgabehistorie. Ausgaben können an ein freigegebenes Mannschaftsmitglied oder
einen aktiven Spieler erfolgen. Das Backend verhindert:

- Ausgaben über den verfügbaren Bestand,
- Empfänger aus einer fremden Mannschaft,
- gleichzeitige Benutzer- und Spielerzuordnung,
- Bestandsreduzierung unter die bereits ausgegebene Menge.

Rückgaben werden mit Zeitpunkt und optionalem Zustandsvermerk gespeichert.
Historische Ausgaben werden nicht gelöscht.

## Checklisten

Vorlagen bilden Abläufe wie Spieltag, Turnier, Auswärtsfahrt, Saisonstart oder
Saisonabschluss ab. Beim Start wird eine unveränderliche Momentaufnahme der
Vorlagenpunkte angelegt. Dadurch bleiben laufende und abgeschlossene
Checklisten nachvollziehbar, auch wenn die Vorlage später angepasst wird.

Pflichtpunkte steuern den Abschlussstatus. Sobald alle Pflichtpunkte erledigt
sind, wechselt der Lauf automatisch auf `COMPLETED`. Jede Änderung speichert
Bearbeiter und Zeitpunkt.

## API

Alle Endpunkte benötigen einen freigegebenen Account:

```text
GET  /team-operations
POST /team-operations/tasks
PUT  /team-operations/tasks/:id
POST /team-operations/equipment
PUT  /team-operations/equipment/:id
POST /team-operations/equipment/:id/assignments
POST /team-operations/equipment-assignments/:assignmentId/return
POST /team-operations/checklist-templates
POST /team-operations/checklist-runs
PUT  /team-operations/checklist-runs/:runId/items/:itemId
```

Anlegen, Zuweisen, Rücknehmen und Abhaken erzeugen Einträge im zentralen
`AuditLog`. Die Migration
`20260729220000_team_operations` legt Aufgaben, Inventar, Ausgabehistorie,
Checklisten-Vorlagen und Checklisten-Läufe an.
