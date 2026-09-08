# FC Teugn Talents 1.7.4 · Mannschaftsübergreifende Nominierungen

Version **1.7.4+189**, vorbereitet am 8. September 2026. Veröffentlichung für Web, Backend und signierte Android-APK auf ausdrücklichen Nutzerwunsch.

## Verhalten

- Eine versandte Spieleinladung gewährt dem Spieler und seinen verknüpften Eltern Zugriff auf genau diesen Termin, unabhängig von Stamm-Mannschaft oder Jugend. Kalender, Spieleübersicht, Dashboard, Spieltag und Liveticker verwenden diesen Zugriff. Er bleibt bei einer erneuten Kaderbearbeitung bestehen; reine neue Entwürfe erteilen keinen Zugang.
- Gastfamilien können Fahrten anbieten, Plätze für Eltern und eingeladene Kinder buchen sowie Bedarf melden. Die automatische, transaktional gesicherte Platzvergabe erkennt Gastspieler. Unbeteiligte Geschwister sind für das fremde Spiel nicht buchbar.
- Die Trainerübersicht zählt sämtliche zum Spiel gehörenden Rückmeldungen und offenen Einladungen, einschließlich Gastspielern und Absagen. Kalenderdetails verwenden denselben Teilnehmerkreis. Entfernte Teilnehmer werden ausgeschlossen; bei relevanten Terminänderungen ist eine frühere Antwort wieder offen.
- Die Spielkarte auf dem Trainerdashboard zeigt Zusagen, Absagen und offene Antworten. Die Beschriftung leerer Dashboard-Karten bricht bei großer Schrift sicher um.
- Bereits eingeladene Gastspieler bleiben beim erneuten Speichern des Kaders verfügbar. Auch die Liveticker-Empfängerliste behält eingeladene Familien während einer Kaderbearbeitung bei.
- Familienfreigaben, interne Trainerinformationen und Mannschaftsverwaltung behalten ihre Berechtigungsgrenzen. Es wird keine Mitgliedschaft im fremden Team angelegt.

## Interne Prüfung

- **718 Flutter-Tests bestanden**, darunter drei neue mobile Regressionen: Gastkind und Elternteil buchen bei 320/390 Pixel Breite mit 200 % Schrift; Gesamtzahlen der Spielkarte bei „Alle Mannschaften“ mit 320 Pixeln und 200 % Schrift.
- **272 Backend-Tests plus drei vorgeschaltete Tests bestanden.**
- Isolierte PostgreSQL-Integration über PGlite einschließlich aller Migrationen und bestehender Talents-Abläufe bestanden. Der neue Ablauf `api/tests/cross-team-match-integration.cjs` verwendet synthetische Familien aus einer anderen Jugend und prüft beide Elternzugänge, Spielerzugang, Spiel/Listen/Kalender/Dashboard/Liveticker, Mitfahrangebot, direkte und automatische Buchung, vollständige Rückmeldungszahlen, tatsächliche Kaderbearbeitung, Nachnominierung, erneute Bestätigung und Entzug des Zugangs. Keine produktiven Testdaten oder Nachrichten an reale Personen.
- Flutter Analyze ohne Befunde; Web-Release-Build erfolgreich. Formatprüfung: 293 Dateien ohne Änderungen. Öffentliche Veröffentlichungsnachweise werden nach der Auslieferung ergänzt.

Keine Mannschaftskasse, keine Veröffentlichung auf Google Play. Native Apple-Veröffentlichung bleibt optional.

Lokale Nachweise: `artifacts/release-1.7.4-build-189/`.
