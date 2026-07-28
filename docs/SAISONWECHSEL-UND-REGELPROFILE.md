# Saisonwechsel und Regelprofile

## Regelprofile

Vereinsadministratoren und Jugendleiter verwalten Regelprofile unter
**Verein & Mannschaften → Vereinsadministration**.

- Jede Änderung erzeugt eine neue Version; ältere Versionen bleiben erhalten.
- Ein neuer Eintrag ist zunächst ein Entwurf.
- Die Freigabe speichert Zeitpunkt und freigebende Person.
- Quelle oder Vereinsbeschluss können am Profil dokumentiert werden.
- Freigegebene Profile werden beim Saisonwechsel als neuer, erneut
  freizugebender Entwurf übernommen.
- Anlage und Freigabe werden im Audit-Log protokolliert.

## Geführter Saisonwechsel

Der Saisonwechsel ist absichtlich zweistufig:

1. **Vorschau erstellen:** Die App berechnet Ziel-Altersklassen, Teams,
   Spielerwechsel, Archive und Mitgliedschaftskopien. Dabei werden noch keine
   Vereinsdaten verändert.
2. **Geprüft ausführen:** Erst nach ausdrücklicher Bestätigung läuft eine
   Datenbanktransaktion. Entweder werden alle Änderungen übernommen oder keine.

Standardmäßig rücken Jugendklassen in der Reihenfolge
`G → F → E → D → C → B → A` weiter. A-Junioren bleiben in der Vorschau in A
und werden mit einem Hinweis versehen, damit Abgänge bewusst archiviert werden.

### Schutz der Historie

- Alte Saison, Altersklassen, Teams, Termine, Ergebnisse und Statistiken werden
  nicht gelöscht.
- `PlayerSeasonAssignment` bewahrt die Teamzuordnung eines Spielers je Saison.
- Die primäre Teamzuordnung wird erst innerhalb der finalen Transaktion
  aktualisiert.
- Sorgeberechtigten-Verknüpfungen hängen am Spieler und bleiben unverändert.
- Freigegebene Mitgliedschaften werden in das neue Team kopiert.
- Der alte Saisonstatus wird erst beim erfolgreichen Abschluss deaktiviert.
- Ein eindeutiger Idempotenzschlüssel verhindert doppelte Ausführung.
- Vorschau, Ergebnis und ausführende Person bleiben als
  `SeasonTransition` nachvollziehbar.

### Fehlerbehandlung

Schlägt ein Einzelschritt fehl, rollt die Datenbank alle fachlichen Änderungen
zurück. Der Vorgang erhält den Status `FAILED` und kann anhand der gespeicherten
Fehlermeldung geprüft werden. Für einen neuen Versuch wird eine neue Vorschau
erstellt.

## API

Alle folgenden Routen benötigen `MANAGE_ORGANIZATION`:

- `GET /organization/rule-profiles`
- `POST /organization/rule-profiles`
- `POST /organization/rule-profiles/:id/approve`
- `GET /organization/season-transitions`
- `POST /organization/season-transitions/preview`
- `POST /organization/season-transitions/:id/apply`
