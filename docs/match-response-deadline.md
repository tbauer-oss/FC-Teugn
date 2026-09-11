# Rückmeldefrist für Spiele

Trainer wählen beim Anlegen und Bearbeiten unter **Kader schließen**: ohne Frist,
24/48/72 Stunden, 7/14 Tage vorher oder ein individuelles Datum mit Uhrzeit.
Die Auswahl zeigt den konkreten Zeitpunkt. Ohne Auswahl bleibt die bisherige
Planung unverändert. Eine bereits erreichte Frist schließt sofort beim Speichern.
Die Frist muss vor dem Spielbeginn liegen.

## Verhalten

- Gespeichert wird `Event.responseDeadline` als absoluter Zeitpunkt; keine Migration erforderlich.
- Ab einschließlich dieses Zeitpunkts sind alle Familienantworten (auch Absagen
  und Zurücksetzen auf offen) serverseitig gesperrt. Bestehende Antworten bleiben erhalten.
- Berechtigte Trainer dürfen weiter korrigieren, auch bei ihren eigenen Kindern.
  In ihrer persönlichen Elternansicht gilt dagegen dieselbe Frist wie für andere Eltern.
- Die Tagesautomatik darf durch eine Familienzusage für einen anderen Termin keine
  Zusage aus einem geschlossenen Spielkader entfernen. Bestehende Sonderfreigaben
  für zwei Spiele bleiben gültig. Automatische Abwesenheiten überspringen geschlossene Spiele;
  Eltern müssen notwendige Änderungen mit dem Trainerteam klären.
- Entfernen der Frist öffnet die Rückmeldungen wieder, sofern sie nicht anderweitig
  abgeschlossen sind. Beim Verschieben des Spiels bleibt der zeitliche Abstand erhalten,
  auch beim Spielplanimport. Bei Turnieren gilt die Frist des Master-Turniers.
- Familienfreigabe, Nominierung, Erinnerungen und Spielinfo enthalten Zeitpunkt und Regel.
  Änderungen an der Frist bereits familienfreigegebener Spiele laufen über die bestehende,
  wiederholbar verarbeitbare Benachrichtigungs-Warteschlange. Push-Zustellung unterliegt den
  bestehenden Nutzer- und Geräteeinstellungen. Keine zusätzlichen Testnachrichten an echte Nutzer.
- Geöffnete Familien-Schnellaktionen und Kalenderbuttons reagieren auf den Fristablauf;
  zusätzlich wird vor der Antwortspeicherung auf dem Server geprüft.

## Dashboard

Trainer und Eltern sehen bei der nächsten Spielkarte **Beginn** und, sofern hinterlegt,
**Treffpunkt** mit Uhrzeit. Die Angaben verwenden lesbare Schrift, dürfen umbrechen
und werden nicht mit Auslassungspunkten gekürzt. Ein Treffpunkt an einem anderen Tag
enthält zusätzlich das Datum. Training, Gegner und Routenanzeige bleiben erhalten.

## Prüfung

- `api/tests/response-deadline-integration.cjs`: isolierte Datenbank, Anlegen/Bearbeiten,
  Sperre aller Antwortwerte, Trainer-/Elternrollen, Tageskonflikt, Frist entfernen,
  Verschiebung und Benachrichtigungen; eingebunden in `npm run test:talents:integration`.
- `api/tests/match-publication.test.js`: Fristgrenze, Eingabevalidierung, Sommerzeit,
  Elterntext und Abstand beim Verschieben.
- Flutter: `response_deadline_test.dart`, `dashboard_match_times_test.dart`,
  `family_response_actions_test.dart` und die Eltern-/Trainer-Dashboardtests prüfen
  Vorauswahl, ablaufende/offene Frist, alte Ansichten und schmale/vergrößerte Layouts.
